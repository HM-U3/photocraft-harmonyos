# 技术笔记（2.0 原生移植）

面向要改代码或提 issue 的人。README 讲怎么用，这份讲为什么这么写、以及踩过的坑。

1.x（WebAssembly + ArkWeb）时期的笔记归档在 [`notes-1.x-webassembly.md`](notes-1.x-webassembly.md)。

## 目录

1. [线程模型与数据流](#1-线程模型与数据流)
2. [surface 与 wgpu](#2-surface-与-wgpu)
3. [让 egui 脱离 eframe](#3-让-egui-脱离-eframe)
4. [输入桥](#4-输入桥)
5. [滚轮：三个独立缺陷](#5-滚轮三个独立缺陷)
6. [输入法](#6-输入法)
7. [系统能力请求队列](#7-系统能力请求队列)
8. [中文字体](#8-中文字体)
9. [调试手法](#9-调试手法)

---

## 1. 线程模型与数据流

```
ArkTS 主线程                          Rust 渲染线程（native.start 起）
─────────────────────────            ──────────────────────────────────
XComponent.onTouch/Mouse/Key  ──┐
onAxisEvent（滚轮）            ├──► Mutex<Vec<InputEvent>>
隐藏 TextInput（IME）          ──┘         │  每帧取空
                                           ▼
80 ms 轮询 takeRequests()  ◄────────  Requests（打开 / 存储为 / 外链）
   │  picker / 系统浏览器
   └─ open_file(name, bytes) ──────►  back to engine
   └─ export_png() ─────────────────►  Buffer（ArkTS 自己写盘）

                              egui::Context ─ run_ui(RawInput) ─ tegui FullOutput
                                           │
                                           ▼  tessellate → wgpu render pass
                                    OHNativeWindow（EGL surface）
```

要点：Rust 侧只暴露**无状态函数 + 队列**，所有 NAPI 调用都不阻塞渲染线程。
`native.start(surfaceId, w, h, dpi)` 起线程，`native.stop()` 收线程；
尺寸变化走 `native.resize`，不重建线程、不丢状态。

## 2. surface 与 wgpu

- `surfaceId` 由 `XComponentController.getXComponentSurfaceId()` 给出，Rust 侧经
  `OH_NativeWindow` 拿到 `OHNativeWindow*`，交给 `wgpu::Surface`。
- 后端固定为 `wgpu::Backends::GL`（EGL/GLES3）—— 鸿蒙设备上 Vulkan 不可用，
  GLES 是唯一稳的路。`PowerPreference::HighPerformance`。
- `present_mode` 与 `format` 取 surface capability 的第一个可用项，不硬编码。
- **DPI**：ArkTS 传 `d.display.densityDPI / 160`（如 2.0、1.5）。渲染线程把它作为
  `egui` 的 `native_pixels_per_point`，`screen_rect` 则用 `尺寸 / dpi`（逻辑点）。
  ArkTS 的 `TouchObject.x/y` 本来就是 vp，所以**触摸坐标与 egui 的点坐标是同一套单位**，
  不需要再乘除 —— 这里搞错会表现为「点击位置整体偏移」。
- 上游 0.37 自带的 view cache（`caches` / `view_cache` / `blit_*`）在原生路径上同样生效，
  缩放时只 blit 一层屏幕尺寸的离屏纹理，不再沿 mip 链重采样。

### 2.1 surface 不会跟着窗口变大（全屏后画面缩在中间、点击偏移）

`XComponent` 的 surface 类型 surface **只在创建时确定一次尺寸**。之后窗口最大化、拖边框、
分屏，变大的只是组件本身，surface 仍然是启动时那块。而且 `SurfaceRect` 不设 `offsetX/offsetY`
时系统按**居中**摆放，于是画面缩在窗口正中、四周一圈背景色 —— 和用户截图完全一致。
连带的第二个症状是触摸坐标（相对组件）与画面像素（来自小 surface）比例不一致，
**全屏后点得越靠边偏得越多**。

要在尺寸变化时自己把 surface 撑开，三步缺一不可：

1. `XComponentController.setXComponentSurfaceRect({ offsetX: 0, offsetY: 0, surfaceWidth, surfaceHeight })`
   —— 单位是 **px**，要 `vp × display.densityPixels`；`offset` 必须显式给 0，否则又回到居中。
2. `OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, w, h)`
   —— 见 §2.2，只改 rect 不够。
3. `Cmd::Resize` 通知渲染线程重配交换链与 `egui` 的 `screen_rect`。

第 2、3 步之后不能再重启渲染线程（否则当前文档没了），所以 `startRender()` 里要先比
`surfaceId`：**id 没变就只 resize，走重启分支才会丢文档**。

顺带一个启动期的坑：`onLoad` 里读到的 surface 矩形可能还是布局前的默认值，
全屏启动时尤其明显。组件用 `onAreaChange` 把尺寸缓存下来，`native.start` 成功后
再用缓存值校正一次。

### 2.2 `setXComponentSurfaceRect` 之后要重设 buffer geometry

只调 `setXComponentSurfaceRect`，画面不会跟着变大 —— swapchain 取帧用的是窗口 buffer 的尺寸，
buffer 没变，画面就还是那么大。Rust 侧每次 `Cmd::Resize` 之前都要：

```rust
ndk::set_buffer_geometry(window, width, height);   // OH_NativeWindow_NativeWindowHandleOpt(SET_BUFFER_GEOMETRY)
surface.configure(&device, &config);
```

日志里对一下 `buffer geometry WxH (rc=0) -> Some((W, H))` 和 `resize WxH @dpi`，
两者都出现才算真的生效。

### 2.3 打开即全屏：先切窗口，再 loadContent

2.0.2 起应用启动就是全屏（`EntryAbility.prepareFullScreen`）。顺序是硬要求：

```ts
onWindowStageCreate(stage) {
  this.prepareFullScreen(stage).then(() => stage.loadContent('pages/NativeRender'));
}
```

`prepareFullScreen` 里调的是 `win.maximize(window.MaximizePresentation.ENTER_IMMERSIVE)`
—— 新版 SDK 已经删掉了 `WindowMode` / `setWindowMode`，全屏只剩这一条路。`ENTER_IMMERSIVE`
会连标题栏和 Dock 一起收起来，光标移到屏幕顶边才浮出来，留一个还原/关闭的出口。
手机 / 平板上系统本来就只有全屏，这个调用报 `801`（能力不支持），`catch` 掉即可。
外面还套了 1.5 s 超时兜底：真机上万一 `maximize` 的 Promise 迟迟不回，页面也不能不加载。

为什么不能「先加载、再切全屏」：surface 的尺寸在创建那一刻就定了（§2.1），
先按默认小窗加载就必然要经历一次「小 surface → resize 撑大」，
中间那一帧画面缩在中间、四周一圈背景色；而先切全屏，`XComponent` 一落地拿到的就是
整屏尺寸，`native.start` 报 `3120x2080`，随后那次 `resize` 只是幂等的复核（同值，rc=0）。

## 3. 让 egui 脱离 eframe

`eframe` 假定自己拥有窗口与事件循环，而鸿蒙上这两样都在 ArkTS 手里。做法：

- `photocraft-ohos` 以 `default-features = false` 依赖 `ui-egui`；
- `crates/ui-egui` 里所有 `eframe::Frame` 的使用点收进 `#[cfg(feature = "eframe")]`，
  宿主入口改成三个约定函数：`logic_frame(ctx)`、`ui_frame(ui)`、`raw_input_frame(ctx, &mut raw)`。

渲染线程的手写循环（伪代码）：

```rust
let raw = RawInput { screen_rect: Some(Rect::from_min_size(Pos2::ZERO, points)),
                     native_pixels_per_point: Some(dpi), events, .. };
let output = ctx.run_ui(raw, |ui| { app.logic_frame(&ctx); app.ui_frame(ui); });
```

注意 `native_pixels_per_point` 必须每帧给，否则 `set_pixels_per_point` 会被下一帧覆盖。

## 4. 输入桥

| 事件 | ArkTS 来源 | NAPI | egui 落点 |
|---|---|---|---|
| 触摸 | `onTouch`（Down/Move/Up/Cancel，单指） | `touch(phase,x,y)` | `PointerButton::Primary` |
| 双指捏合 | `onTouch` 里按 `changedTouches` 维护的手指 id 表 ≥ 2 | `pinch(scale,cx,cy)` | `PointerMoved(center)` + `Event::Zoom` |
| 鼠标 | `onMouse`（Press/Release/Move） | `mouse(phase,button,x,y)` | 同上，区分右/中键 |
| 滚轮 | `onAxisEvent` | `wheel(dx,dy,ctrl,shift,alt)` | `Event::MouseWheel` |
| 键盘 | `onKeyEvent` | `key(phase,code,ctrl,shift,alt,text)` | `Event::Key` + `Event::Text` |
| IME | 隐藏 `TextInput` 的 `onChange` | `ime_text` / `ime_backspace` | `Event::Text` / 退格 |

修饰键有两条来源：自己跟踪 key-down/up，以及系统的 `getModifierKeyState`。
**以系统为准，自己跟踪只在系统返回 `undefined` 时兜底** —— 反过来的话，一次丢失的 key-up
会让 `Ctrl` 永远卡住，之后所有点击都变成「加选」。

滚轮去重键是 `时间戳|动作|dx|dy` 四元组。XComponent 与 `onTouch`/`onAxisEvent` 的双挂载
会让同一个事件派发两次；但只比时间戳会把同一毫秒里真实发生的不同事件也吞掉。

## 5. 滚轮：三个独立缺陷

「Ctrl + 滚轮不能放大 / 滚一格没反应 / 放大是跳的」这三个现象由三处独立问题叠加而成，
修好任意两处都不会好。

### 5.1 慢速滚动把增量报在 END 上

HarmonyOS 的轴事件按 `BEGIN … UPDATE … END` 分段。**慢速滚一格时，增量常常只出现在 END 上**，
中间的 UPDATE 全是 0。早先的 `onWheel` 开头就是 `if (action === END || CANCEL) return;`，
于是滚一格等于什么都没发生，只有快速连滚（连续 UPDATE）才动。

修法：只丢 CANCEL；用「本次手势是否已上报过数值」记账，已报过的段忽略 END 的同值重复，
整段没报过时 END 就是全部。

### 5.2 换算系数与实际数值

设备实测：滚一格轴值 `dy = ±45`（= 3 × 15°），ArkTS 侧统一乘 2.6 → **117 pt/格**。
egui 把 `MouseWheel.delta` 当作内容方向的点位移（向上为正），而 `getVerticalAxisValue`
向下为正，所以 Rust 侧**取负**。

由此一格平移 117 pt；`Ctrl` + 一格缩放 `1.1^(117/40) ≈ ×1.32`
（相当于系统设置里「一次滚 3 行」）。要更细腻就把 ×2.6 调小，一档会更接近 ×1.1。

### 5.3 缩放跳变：不要另起一套公式

早期把 `Ctrl` + 滚轮直接合成 `Event::Zoom(f)`，绕过了 Animated Zoom 的缓动，
所以是「跳」而不是「滑」；而且那个公式假设 `delta` 是点，遇到按「行」上报的宿主时
一格只有 ×1.0002。

修法：`ctrl_wheel_to_alt` **只改写修饰键** —— `Ctrl` + 滚轮当作 `Alt` + 滚轮读，
剩下交给既有的分类逻辑：一档 ×1.1、方向与桌面版一致、同样走缓动。
滚轮只有一套策略，改一处即可。桌面端不受影响（这条只有独立宿主会调）。

## 5.4 双指捏合

egui 没有「两根手指」这个概念，捏合在它那里就是一个 `Event::Zoom(倍数)`；而画布缩放以
**指针位置**为锚点。所以宿主把一次捏合拆成两个事件：先 `PointerMoved(两指中点)`，
再 `Event::Zoom(本次间距 / 上次间距)`。

这样缩放走的是轨道板捏合同一条路径（`wheel_nav` 把 `zoom_delta` 读成 `Wheel::Zoom`），
于是 `Enhanced Controls › Zoom with Trackpad Pinch` 开关、缩放上下限、指针锚点全部沿用，
不需要在画布侧再写一套。捏合是逐帧跟手的，所以不带 Animated Zoom 的缓动。

ArkTS 侧有三处必须注意：

1. **用增量，不用手势的累计 `scale`**。`Event::Zoom` 本身是倍数因子，逐帧相乘即可；
   存手势起点反而要在手指数变化时重新取基准。
2. **第二根手指落下时要收回已经按下的那一笔**（发 `native.touch(3, …)`，即 Cancel）。
   第一根手指的 Down 早在几十毫秒前就转发成 `PointerButton{ pressed: true }` 了，
   不收的话整个捏合过程中笔刷会跟着第一根手指一路画过去。
3. **手指数量不能数 `event.touches.length`**。抬起的那个在部分版本里仍留在 `touches` 里，
   「所有手指都离开了」永远等不到，捏合标志卡死、之后单指再也画不了线（现象很吓人：
   捏合之后整个画布失去响应）。改成用 `changedTouches` 维护一张 id 表，按下加、抬起删，
   再拿 `touches.length === 0` 兜底清空。
4. **手指没全抬起来之前，单指事件一律不转发**。捏合途中抬起一根手指，
   剩下的那根不是「新的一笔」；要等 id 表空了再恢复。

宿主侧对应的坑：`Event::PointerGone` **不等于抬起**。egui 故意在收到 `PointerGone` 时
保留 pressed 状态（这样把滑块拖到窗口外还能继续拖），所以只发 `PointerGone` 的话，
第一根手指的拖动仍然活着，捏合发出的 `PointerMoved(中点)` 就变成了一次拖动 ——
画布上留下一条甩不掉的虚线选区。正确做法是 Cancel 时先补一个
`PointerButton{ pressed: false }`（位置就是那根手指，长度为零的一次「点击」），再发
`PointerGone`。宿主为此刻意记了一个 `POINTER_DOWN`，没有按下时不会乱发抬起。

## 5.5 文档画布的 CPU 路径

上游有两条画布路径：GPU 画布（wgpu compute 出 tile）和 CPU 画布（CPU 合成后当 egui 纹理上传）。
CPU 路径本来就在树里，`gpu_status::fall_back` 在 GPU 画布丢失或显存不足时会自动切过去。

宿主此前无条件 `set_wgpu()`，所以 `Preferences › Performance › Rendering Mode = cpu` 在鸿蒙上是
空转的（上游桌面版是在启动时按这个偏好决定要不要 `set_wgpu`）。现在宿主同样按偏好判断：
选 `cpu` 时只 `watch_window_device()`（窗口仍用 wgpu 画，设备丢失与错误照常记录），
画布走 CPU 合成。偏好改完要重启应用才生效。

需要说清的是：这条 CPU 路径只管**文档像素的合成**。整个界面是宿主用 wgpu 直接画进
`XComponent` 的，没有软件光栅的替代实现 —— wgpu 设备完全建不起来时应用无法启动，
这不是「没移植 CPU 后端」，而是窗口层本来就只有 GPU 一条路。

## 6. 输入法

ArkTS 没有「直接给某个坐标送一个字符」的能力，只能借一个真实的文本输入组件：

1. 每 80 ms 问一次 `wants_text_input()`；为真时才把 2×2、`opacity 0.01` 的
   `TextInput` 插进组件树并请求焦点 —— 常驻的话它会自己抢焦点，一点画布就弹键盘。
2. `onChange` 拿到上屏后的**全量文本**，与上一次的值求公共前缀：
   先 `ime_backspace(旧长度 - 前缀)`，再 `ime_text(新值.substring(前缀))`。
   这样「全选后输入」也能正确替换。
3. 引擎不再需要输入时收回焦点并清空缓存值，下次打开输入法不会带着旧文本。

## 7. 系统能力请求队列

引擎的「打开 / 存储为 / 外链」在纯 Rust 里无解（没有文件对话框，也没有浏览器）。做法：

- Rust 侧 `request("pickOpen")` / `request("saveAs:<name>")` / `request("openUrl:<url>")`
  把字符串排进 `REQUESTS`；
- ArkTS 每 80 ms `takeRequests()` 取走，弹 `picker.DocumentViewPicker` 或 `SaveButton` 流程；
- 打开：`fileIo` 读成 `ArrayBuffer` → `open_file(name, buffer)`；
- 保存：`export_png()` 返回 `Buffer` → ArkTS 写到用户选定的路径（同一文件第二次保存直接复用路径）；
- 外链：`openUrl` 交给系统浏览器，编辑器页面不会被顶掉。

轮询间隔是权衡：80 ms 对「点菜单后多久弹选择器」已经无感，又不至于空转浪费。

## 8. 中文字体

引擎自带字体没有 CJK 字形。宿主按顺序探测系统字体并注册为**最低优先级**回退：

```
/system/fonts/HarmonyOS_Sans_SC.ttf
/system/fonts/NotoSansCJK-Regular.ttc      （.ttc 里挑 "Noto Sans CJK SC" 那个 face）
/system/fonts/NotoSansSC-Regular.otf
```

要注册到 4 个字族：`Proportional`、`Monospace`，以及 PhotoCraft 文字工具用的命名族
`medium` / `semibold` —— 它们各自维护字体栈，漏了就会在这两处出现豆腐块。

好处是不用打包字体（1.x 内嵌了 549 KB 子集，还带来 OFL 保留字体名的合规问题），
拉丁字形仍走引擎自带字体，观感不变。三个路径都读不到时打一条
`no system CJK font found, typed Chinese may show as tofu`。

## 9. 调试手法

真机上没有 DevTools，全靠 `hdc`：

```bash
HDC="D:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"

# 日志（务必先去掉 \0 和换行再 grep，hilog 的长行会被截断成多段）
"$HDC" shell "hilog -x" | tr -d '\0' | tr '\n' ' ' | grep -o "wheel dx=[-0-9.]* dy=[-0-9.]* ctrl=[a-z]*"

# 注入滚轮一格（-s/--scroll）
"$HDC" shell "uinput -M -s 1"
# 注入 Ctrl（2072 = 左 Ctrl 按下）
"$HDC" shell "uinput -K -d 2072"
# 点击：uitest 比 uinput -M -c 可靠（后者经常点不中）
"$HDC" shell "uitest uiInput click 1011 939"
# 截图
"$HDC" shell "snapshot_display -f /data/local/tmp/s.jpeg"
"$HDC" file recv /data/local/tmp/s.jpeg ./s.jpeg
```

排查顺序建议：**先在宿主里打临时日志确认「Rust 收到了什么」**，再看 egui 的反应
（`ctx.input(|i| i.zoom_delta())`、`i.smooth_scroll_delta`）。这次的滚轮问题就是靠
`zoom_delta=1.3215` 证明换算无误，把范围锁死在 ArkTS 侧。

以下几条是实测结论，别再踩：

| 事项 | 结论 |
|---|---|
| `uinput -M -s` | **可以**注入滚轮（早期笔记里写「没有滚轮注入命令」是错的） |
| `uinput -M -c` | 点不中，用 `uitest uiInput click x y` |
| 设备锁屏 | `aa start` 会被拒（`10106102 screen is locked`），需手动解锁 |
| 追踪耗时 | 上游的 `Perf` 计时在非桌面平台上多为 0 值桩，真机诊断用「工作类型」而不是耗时 |
| `hilog -x` 输出 | 单行可能极长且带 `\0`，直接 `grep` 会漏；先 `tr -d '\0'` |
