# 技术笔记（2.0 原生移植）

面向要改代码或提 issue 的人：为什么这么写，以及踩过的坑。

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
一部分形态（如手机、部分 PC 模式）上调它会报 `801`（能力不支持），`catch` 掉即可。
外面还套了 1.5 s 超时兜底：真机上万一 `maximize` 的 Promise 迟迟不回，页面也不能不加载。

**只调 `maximize` 并不等于「看不见系统栏」。** 2.2.1 在 MatePad Edge 上实测：`maximize`
回来后 `windowRect` 确实是 `3120x2080`（整屏），但 `XComponent` 的 surface 只有 `3120x1934`
—— 差的 146 px 正好是状态栏高度，也就是窗口铺满了、布局却仍然在给系统栏让位，状态栏和底部
导航条照旧画在最上层。补两步才彻底：

```ts
await win.setWindowLayoutFullScreen(true);   // 布局层铺到系统栏底下
await win.setWindowSystemBarEnable([]);      // 再把状态栏、导航条本身隐藏
await win.maximize(window.MaximizePresentation.ENTER_IMMERSIVE);
```

两步都放在 `maximize` **之前**，等它们落定再 `loadContent`，surface 一创建就是 `3120x2080`。
几条实测结论：

- 只加 `setWindowLayoutFullScreen(true)` 不够：surface 会变 `3120x2080`，但状态栏仍然绘制在
  内容之上（时间、电量压在菜单栏左边），底部导航条也在。
- 换成 `setSpecificSystemBarEnabled('status'|'navigation', false)` 也不行：状态栏没了，底部
  导航条的横线还在，而且编译期同样报两条「unavailable to 2in1」。
- `setWindowSystemBarEnable([])` 是唯一两步都干净的写法，代价是一条编译告警
  （`WindowManager.Core` 的 syscap 对 2in1 标记为不可用）。桌面形态本来就没有状态栏，
  走 `maximize` 的沉浸式即可，真报错会被 `catch` 吞掉。

为什么不能「先加载、再切全屏」：surface 的尺寸在创建那一刻就定了（§2.1），
先按默认小窗加载就必然要经历一次「小 surface → resize 撑大」，
中间那一帧画面缩在中间、四周一圈背景色；而先切全屏，`XComponent` 一落地拿到的就是
整屏尺寸，`native.start` 报 `3120x2080`，随后那次 `resize` 只是幂等的复核（同值，rc=0）。

### 2.4 系统标题栏的「最大化」不是全屏

启动时我们调 `maximize(ENTER_IMMERSIVE)`，拿到的是 `WindowStatusType.FULL_SCREEN`（3120×2080，
标题栏与 Dock 都收起）。但用户在系统标题栏上点最大化按钮时，系统按默认语义走，得到的是
`WindowStatusType.MAXIMIZE` —— 铺满宽度，**底部留着 125 px 的 Dock，顶边还能浮出标题栏**，
和启动时的观感完全是两回事。`maximize()` 的 `presentation` 只对那一次调用生效，不会写进应用设置。

修法是在 `windowStatusChange` 里盯住 `MAXIMIZE`，补一次 `ENTER_IMMERSIVE`。两个细节不能省：

1. **必须等布局落定**。状态回调到达时窗口还在做最大化动画，此刻立刻调 `maximize` 只会把状态位
   改成 1，尺寸仍停在 3120×1955。等 350 ms 再调，才拿得到 3120×2080。
2. **`windowRect` 会滞后**。`maximize()` 的 Promise 回来时读到的是旧值（1955），要再等 600 ms
   复核；确实没到整屏就重试一次（最多两次），免得个别机器动画更长时又缩回去。

日志里对一下 `windowStatus=2 → 1`、`沉浸式校验 3120x2080 屏幕高=2080`，以及 WMS 侧
`NotifyWindowStatusDidChange ... rect:[0 0 3120 2080]`，三者齐了才算真的全屏。

## 3. 让 egui 脱离 eframe

`eframe` 假定自己拥有窗口与事件循环，而鸿蒙上这两样都在 ArkTS 手里。做法：

- `photocraft-ohos` 以 `default-features = false` 依赖 `ui-egui`；
- `crates/ui-egui` 把 `eframe` 变回**可选特性**。关掉后 crate 自己 `extern crate self as eframe;`，
  再把 `egui-wgpu` / `wgpu` 以 `eframe` 之名 re-export —— 于是几百处
  `eframe::wgpu::Device`、`eframe::egui_wgpu::RenderState` 这类路径原样成立，不必逐处改写；
- `eframe::Frame` 由 crate 内的桩顶替（`Frame` / `FrameInfo`），只提供 `info().cpu_usage`
  与 `winit_window()`，后者在鸿蒙上恒为 `None`；
- 输入钩子从 `eframe::App::raw_input_hook` 拆成固有方法 `raw_input_frame`，trait 那边委托过来：
  独立宿主调得到，两条路径也不会各自演化；
- 宿主每帧自己造一个 `Frame::default()`，并按 eframe 的顺序补上 `finish_type_reset_logic`
  与 `finish_type_reset_pass` 两个收尾 —— 少了它们，IME 编辑状态会在编辑器关掉后残留。

渲染线程的手写循环（伪代码）：

```rust
let mut frame = photocraft_ui_egui::Frame::default();
app.raw_input_frame(&ctx, &mut raw);
let output = ctx.run_ui(raw, |ui| {
    let ctx = ui.ctx().clone();
    app.logic_frame(&ctx, &mut frame);
    app.finish_type_reset_logic(&ctx);
    app.ui_frame(ui, &mut frame);
    app.finish_type_reset_pass(ui.ctx());
});
```

注意 `native_pixels_per_point` 必须每帧给，否则 `set_pixels_per_point` 会被下一帧覆盖。

### 3.1 上游跳到 v0.23.1 时踩到的

从 v0.16.0 基线跨到 v0.23.1（6136 个提交），编译层面只有两处真的会挡路：

1. **`eframe` 从可选变回硬依赖**。新版把它当无条件依赖，`eframe::Frame` 也不再带
   `#[cfg(feature = "eframe")]`。鸿蒙没法编 winit，只能把可选特性加回去（见上）。
2. **`raw_input_hook` 从固有方法降级成 trait 方法**。独立宿主够不到，只能拆出
   `raw_input_frame` 让两边共用同一份实现。

顺带把「Ctrl + 滚轮 = 缩放」从 `ui-egui` 挪进宿主：新版 `wheel_nav::classify` 里
`Ctrl` 仍被当成横向滚动，而宿主本来就自己构造 `Event::MouseWheel`，
在那一处把修饰键改成 `Alt` 更省事，也不用再改上游共享代码。

`craft-libs` 的外部依赖同期从 5 个涨到 15 个（`craft-ui`、`craft-print`、`craft-heif`、
`craft-pdf`、`craft-jpeg`、`craft-pcraft-format` 等），全部钉在 git rev 上；
它们都能编到 `aarch64-unknown-linux-ohos`，但首次构建要联网取一次，之后才能 `--offline`。

### 3.2 界面语言：语言包在构建期从外部仓库嵌入

v0.23 起，界面译文不在本仓库里。`crates/ui-egui/build.rs` 从环境变量 `CRAFT_I18N_DIR`
指向的 [storytold/craft-i18n](https://github.com/storytold/craft-i18n) 检出目录里读
`locales/<code>/{common.tsv,photocraft.tsv}`，生成 `OUT_DIR/craft_i18n.rs` 后用 `include_str!`
编进二进制。**不设这个变量时 build.rs 只打一条 warning，产出的库是纯英文界面**——
2.1.0 就是这么发出去的，界面上一个中文字都没有。锁定提交在仓库根的 `craft-i18n.rev`。

重建引擎时必须带上：

```bash
# 一次性：按 craft-i18n.rev 取检出（codeload 直连比 gh-proxy 稳）
curl -L -o ci.tar.gz https://codeload.github.com/storytold/craft-i18n/tar.gz/$(cat craft-i18n.rev)
mkdir -p /d/pcbuild/craft-i18n && tar -xzf ci.tar.gz -C /d/pcbuild/craft-i18n --strip-components=1

# 每次构建
export CRAFT_I18N_DIR="D:/pcbuild/craft-i18n"      # 必须是 Windows 风格路径
cargo build --release -j 8 -p photocraft-ohos --target aarch64-unknown-linux-ohos
```

自查：生成的 `target/<triple>/release/build/photocraft-ui-egui-*/out/craft_i18n.rs`
只有一两行说明是空表（英文版），有 50 多行 `("ar", …)` 才是带译文的。代价是
arm64 库从 74 MB 涨到 84 MB（52 种语言的原样 TSV 全集）。

语言偏好的默认值是 `auto`，由 `ui-egui` 的 `system_lang()` 解析。上游在 Unix 上走
`sys_locale`，读的是 `LANGUAGE`/`LC_ALL`/`LC_MESSAGES`/`LANG` 环境变量——鸿蒙应用进程
继承不到这些变量，所以宿主在渲染线程启动前把系统语言通过 `native.setLocale(tag)`
传下去，落到上游已支持的 `PHOTOCRAFT_LOCALE` 覆盖上（日志 `system locale zh-Hans`）。
顺序是硬要求：`system_lang()` 用 `OnceLock` 缓存，晚于首帧就没用了。

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

修法：**只改写修饰键** —— 宿主把轴事件转成 `Event::MouseWheel` 时，把 `Ctrl` + 滚轮改成
`Alt` + 滚轮，剩下交给既有的分类逻辑：一档 ×1.1、方向与桌面版一致、同样走缓动。
滚轮只有一套策略，改一处即可。桌面端不受影响（这条只有独立宿主会走）。

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

## 10. API 版本：target 26，兼容下限仍是 12

`build-profile.json5` 现在是 `compileSdkVersion 26.0.0` / `targetSdkVersion 26.0.0` /
`compatibleSdkVersion 5.0.0(12)`。两个数字分开的原因：

- `targetSdkVersion` 是**系统的前向兼容开关**。做过版本隔离的行为变更只对
  `targetSdkVersion ≥ 变更版本` 的应用生效；不升就会一直跑在旧行为上，早晚被系统更新搞坏。
- `compatibleSdkVersion` 决定**能装在哪**。2in1 用户里还有一批 HarmonyOS 5.0 的机器，
  降到 18 或 23 就等于把它们排除在外。

代价是：任何比 12 新的 API 都会在编译期得到一条
`The 'xxx' API is supported since SDK version N` 的告警。官方推荐的消音写法是
`deviceInfo.apiAvailable('N.0.0')`，但**它自己就是 API 26 才有的**（`@ohos.deviceInfo`
@since 26.0.0），在 12~25 的设备上调它就是崩，所以只在 target ≥ 26 时能无条件用。

本工程的处置：

| 位置 | 做法 |
|---|---|
| 轴事件（滚轮） | `AxisEvent` / `AxisAction` 是 API 17 的类型，改成自己声明的最小接口 `AxisEventCompat` + `AxisAction` 的数值镜像（0/1/2/3）。老系统上这些属性读到 `undefined`，比较不成立，等于「没有滚轮」，不抛异常 |
| `getSystemLocale()` | 自 API 20 弃用（`getSystemLocaleInstance()` 取代）。改用 **API 9 的** `getPreferredLanguageList()[0]`：给的是完整标签（`zh-Hans-CN`），还分得清简繁；`getSystemLanguage()` 只到 `zh`，繁体会被当成简体 |
| `getContext(this)` | 已弃用，改 `this.getUIContext().getHostContext()`（见 `hostContext()`） |
| `Circle().fill()` | SDK 26 把 `Circle.fill` 的声明换成了 `ResourceColor \| ColorMetrics`（@since 26.0.0），兼容 12 的工程里一直告警。隐私页那颗 4×4 圆点改成 `Row` + `borderRadius` + `backgroundColor`，效果一样 |
| 原生库导入 | 补 `entry/src/main/cpp/types/libphotocraft_native/{index.d.ts,oh-package.json5}`，并在 `entry/oh-package.json5` 里以本地依赖引入。之后 `native.*` 有类型，改错名字编译期就报错；否则导入是 `any`，且 hvigor 每次提示「module ... is not verified」 |

**仍剩 2 条告警**：`XComponent.onAxisEvent` 本身是 API 17 的属性方法。属性方法没法用
`if` 条件挂载（要么走 `AttributeModifier` 把整段逻辑包起来，要么接受告警），而
`apiAvailable` 又只在 26+ 存在 —— 在兼容 12 的前提下这两条无法消除。API 12~16 的设备上
滚轮本来就不生效（系统不派发轴事件），代码里的 try/catch 与数值判断已经兜住了。

新增本地类型依赖后要跑一次 `ohpm install --all`，否则 `entry/oh_modules` 是空的、
声明不会生效（hvigor 不会自动装 file: 依赖）。
