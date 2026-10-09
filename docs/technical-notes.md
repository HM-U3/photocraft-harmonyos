# 技术笔记

移植细节、缺陷根因与验证数据。README 面向使用者，这份文档面向要改代码或提 PR 的人。

## 目录

1. [引擎重编译与中文化](#1-引擎重编译与中文化)
2. [鸿蒙适配细节](#2-鸿蒙适配细节)
3. [缺陷：缩小时画面变透明](#3-缺陷缩小时画面变透明)
4. [缺陷：保存、导出与外链无反应](#4-缺陷保存导出与外链无反应)
5. [缺陷：开着导航器时编辑极卡](#5-缺陷开着导航器时编辑极卡)
6. [重新编译引擎](#6-重新编译引擎)
7. [提交前自查](#7-提交前自查)

---

## 1. 引擎重编译与中文化

### 1.1 为什么不能直接改 wasm

最初拿到的是预编译的 `photocraft-web-*_bg.wasm`（约 26 MB）。在其中检索后确认：
除依赖库残留（`naga` 的 GLSL 诊断信息、SVG 属性名）之外，**没有任何语言列表、locale 切换
或 i18n 框架**，`Language` / `zh-CN` 都是误命中。逐一核对上游中文词条后，结论是
**二进制原地替换不可行**：

| 指标 | 结果 |
|---|---|
| 中文词条总数 | 2045 |
| 在 v0.2.0 的 wasm 中根本不存在的词条 | 367（18%） |
| 能定位到 `{ptr, len}` 静态对、可原地改写的 | 393 / 1678 |
| 理论最大原地覆盖率 | 989 / 2045（且多数无法定位长度字段） |

即：即便把能改的都改了，仍有超过一半界面是英文，且改写长度受限（不能变长）。
所以最终走**从源码重新编译**这条路。

### 1.2 上游其实自带 i18n

上游有完整的 i18n 框架（`crates/ui-egui/src/i18n/`），并带 `zh-hans.tsv`、`zh-hant.tsv`、
`ja.tsv` 等词条表（简体中文 2067 行，术语是教科书式的 文件 / 编辑 / 图像 / 图层 / 文字 / 选择 / 滤镜）。
问题在于简体中文词条表是在 v0.2.0 发布**之后**才合入的（PR #282），所以发布包里的 wasm 不含中文。

### 1.3 相对于上游源码的改动

全部改动集中在 `tools/build_engine_zh/engine-zh.patch`：

1. **默认语言改为简体中文** —— `crates/engine/src/prefs.rs` 中 `Interface::default()`
   的 `language` 由 `"auto"` 改为 `"zh-hans"`。引擎保留完整语言切换能力，
   用户可在「首选项 › 界面 › 语言」改回任意语言。
2. **内嵌中文字体** —— `crates/text/src/fonts.rs` 增加 `NOTO_SANS_SC` 静态资源并注册到 `BUNDLED`。
   这一步是必需的：上游 Web 构建**从不内嵌 CJK 字体**（`cjk_fonts.rs` 在 `wasm32` 下返回空列表），
   也读不到系统字体，不内嵌的话中文会整片渲染成空白/豆腐块。
3. **把中文字体接进 egui 字族** —— `crates/ui-egui/src/theme.rs` 的 `install_fonts_with` 中
   注册 `NotoSansSC`，追加到 `Proportional` / `Monospace` 两条回退链末尾（英文仍走原有字体）。
4. **GL 后端的 mip 链处理** —— 见 [§3](#3-缺陷缩小时画面变透明)，单独抽成
   `mip-gl-fix.patch` 便于向上游提交。

### 1.4 中文字体子集

**Noto Sans SC**（OFL 1.1）可变字体在 `wght=400` 处实例化后子集化：**549 KB / 2348 字形**，
覆盖引擎全部语言词条表用到的字符 + ASCII + 拉丁扩展 + 标点/箭头/数学符号 + CJK 标点与全角字符。
子集化脚本：`tools/build_engine_zh/gen_cjk_subset.py`。

产物经 `wasm-opt -Oz` 压缩后约 **24.5 MB**（比原 26 MB 发布包还小），
已在同款 Web 内核（无头 Edge + CDP）下确认界面完整渲染为中文、无豆腐块，菜单展开后同样全中文。

---

## 2. 鸿蒙适配细节

### 2.1 胶水层：为什么不用 ES Module

上游 `index.html` 用 `<script type="module">` + `import` 加载胶水层，但 **ArkWeb 的 ES Module
加载器不支持 `resource://` 协议**，真机上直接报：

```
Failed to fetch dynamically imported module:
resource://rawfile/photocraft/photocraft-web-<hash>.js
```

规避办法是把胶水层从 ESM **等价转换**成经典脚本（`*.classic.js`），再由页面用
`document.createElement('script')` + `textContent` 内联注入 —— 不经过模块加载器，任何 WebView 都能跑。

转换只有三处，未改动任何引擎逻辑（未改 `.wasm`，也未改上游 `.js`）：

| 原（ESM） | 现（经典脚本） |
|---|---|
| `export { initSync, __wbg_init as default };` | `window.__PhotoCraftModule = { initSync, default: __wbg_init };` |
| `new URL('..._bg.wasm', import.meta.url)` | `new URL('..._bg.wasm', document.baseURI)` |
| 顶层模块作用域 / 隐式严格模式 | 外层包一层 `(function () { 'use strict'; ... })()` |

重新生成方式（升级引擎时用）：

```bash
python tools/build_engine_zh/gen_classic_glue.py <新的 xxx.js> <xxx.classic.js>
node --check <xxx.classic.js>      # 确认是合法经典脚本
```

### 2.2 资源读取三层容错

`resource://rawfile` 下不同设备/版本对 `fetch`、`XHR` 的支持存在差异，因此页面按三层依次尝试：

1. `fetch()` 流式读取（可显示精确进度）；
2. `XMLHttpRequest`（`responseType: 'arraybuffer'`）；
3. **原生分块通道** —— 通过 `javaScriptProxy` 注入的 `pcBridge.assetSize()` / `pcBridge.assetChunk()`，
   由 ArkTS 侧用 `resourceManager.getRawFileContentSync()` 读取 rawfile，按 1 MiB 分块以 base64 回传。

任一层成功即可启动引擎；三层全失败时页面显示错误详情（同时上报原生侧，
原生会给出「重新加载」/「改用 WebGL2」入口）。

wasm 读完后以字节形式交给胶水层（`init({ module_or_path: bytes })`），
**不让胶水层自己去 fetch `resource://` 下的 wasm**，从而绕开同样的协议限制。

### 2.3 渲染后端如何真正生效

引擎在 Rust/wgpu 内部按 `navigator.gpu` 是否存在选择后端。因此选「WebGL2」时，
页面会在初始化前把 `navigator.gpu` 抹掉（`Object.defineProperty(navigator, 'gpu', ...)`），
这是该选项能真正落到引擎上的唯一手段；选项值本身仍由 ArkTS 经 `pcBridge.renderMode()` 下发。

关键步骤都会经 `pcBridge.log()` 写入 hilog，在 DevEco 的 Log 面板搜 `[PhotoCraft]` 可见
（例如 `引擎胶水层：经典脚本通道 OK`、`fetch 失败(...)，尝试 XHR`），便于定位卡在哪一层。

---

## 3. 缺陷：缩小时画面变透明

### 3.1 现象

HarmonyOS 平板（WebGL2 后端）上把图片缩小到大约 **40% 以下**时画面开始变淡，
到 17.8% 时图像区域整片变成**透明棋盘格**，但右侧「导航器」里的缩略图完全正常。

对录屏逐帧量化后确认了阈值（`checker%` = 画布区域里透明棋盘格像素的占比）：

| 缩放 | 46.5% | 42.7% | 32% | 24.8% | 17.8% | 12.9% | 9.1% | 25.5% | 46% |
|---|---|---|---|---|---|---|---|---|---|
| checker% | 2.5 | 2.3 | 3.8 | 14.6 | **26.0** | 14.7 | 7.9 | 16.2 | 2.5 |

（2~3% 是界面本身的底色，不是画布。）再放大回去就恢复。阈值与 `gpu_canvas.rs` 里
`filter_mode()` 的 LOD 计算完全对得上：`scale = zoom × ppi`，`scale < 1` 时按 `-log2(scale)`
采样 mip 链，LOD 越过 1 就进入 mip 1、越过 2 就进入 mip 2。

### 3.2 根因：GL 上的 mip 链反馈环

结论是**采样的 mip level ≥ 1 全为 0**（alpha = 0 → 画布着色器显示透明棋盘格），
mip 0 是好的，所以只要 LOD < 1（缩放够大）就一切正常。

原因在上游的 `crates/ui-egui/src/gpu_canvas.rs::DocTextures::regenerate_mips`：
它逐级生成 mip 链，生成第 `n` 级时**把源（第 `n−1` 级）和渲染目标（第 `n` 级）放在同一张
GL 纹理上** —— 采样它的同时渲染进它。

- 在 **WebGPU** 上这是合法且有明确定义的（wgpu 保证同一提交内的读写顺序），
  所以桌面浏览器的 Web 版一切正常；
- 在 **OpenGL ES / WebGL2** 上这是未定义行为。wgpu-hal 的 GLES 后端用
  `TEXTURE_BASE_LEVEL` / `TEXTURE_MAX_LEVEL` 把采样范围收窄到单级来"规避"它
  （`wgpu-hal-30.0.1/src/gles/queue.rs:1584`），桌面 ANGLE 会按这个范围判定、放行；
  但移动端 GL 驱动（ANGLE over Vulkan、部分原生 GLES 栈）常常直接把这次 draw 丢掉，
  附件保持 `glTexStorage2D` 时的零值 —— 整级 mip 就变成全透明。

复现差异也印证了这一点：同一版本在桌面（ANGLE/D3D11 **和** SwiftShader 两套 GL 实现）
从 46% 一路缩到 10% 都完全正常，`gl.getError()` 全程为 0，只有真机出问题。

### 3.3 修法：不修 mip 链，改成一层显示缓存

前三版都在问"怎么把这条 mip 链建出来"。第四版换了个问题：**缩小的画面根本不需要每帧重算**。
`crates/ui-egui/src/gpu_canvas.rs` 由此拆成两层：

1. **文档纹理不再有 mip 链**（`mip_level_count = 1`）。反馈环、`GL_MIP_LEVELS`、scratch 纹理、
   `copy_texture_to_texture` 全部消失 —— 画面变透明的根因是被**删掉**的，不是绕过去的。
2. **新增一层屏幕尺寸的离屏缓存**（`ViewCache`，格式与屏幕一致所以 blit 无需转换），
   里面是当前视图下画布的最终像素：棋盘格、投影、显示 LUT、32 位预览都已合成进去。
3. **每帧只做一次 blit**：把缓存 1:1 贴到屏幕（1 次采样，无过滤）。
4. **缓存什么时候重绘**：视图没动且文档没动 → 不重绘；编辑了一笔 → 只重绘 damage 在屏幕上
   对应的那块矩形（缩小状态通常几十像素）；缩放、平移、改窗口、换显示 LUT → 整屏重绘一次。
5. **缩小时用什么过滤**：没有 mip，着色器按 `1/scale` 自己在 level 0 上做 n×n 次采样
   （最多 3×3 = 9 taps）。这笔开销只在重绘那一帧付，blit 帧不付。

于是"编辑一笔"的成本从 **3 次 pass + 3 次纹理拷贝** 变成 **1 次小矩形 pass**；
"缩放/平移"的成本从 1 次 mip 采样变成 1 次 box filter，且只在视图变化的那一帧发生。

关键的性质变化：**每帧的采样开销和每次编辑的重建开销被解耦了**。前几版之所以反复失败，
正是因为这二者被绑在同一条 mip 链上 —— 想让重建便宜就得砍链，砍链又让每帧变贵。
缓存层把"多久重算一次"变成一个可以自由选择的量，而不是 mip 链的结构所决定的量。

> **前三版（都已放弃）**
>
> - **v1「scratch + 完整 11 级链 + 着色器兜底」**：逻辑正确，但编辑变得很卡 ——
>   11 次拷贝 + 每个像素多一次 level 0 大跨度采样（兜底）叠加。
> - **v2「GL 不用 mip 链，着色器在 level 0 上做 2×2 共 4 次采样」**：编辑路径零开销，
>   但比 v1 **更卡** —— 采样从"1 次小纹理"变成"4 次大纹理大跨度采样"，缩小时每个屏幕像素都是 cache miss。
> - **v3「保留链但只建 4 级，GL 上 scratch + 回拷」**：画面正确、拷贝降到 3 次/笔，
>   但每笔仍有 3 次拷贝的固定开销（GL 上没有 `glCopyImageSubData`，一次拷贝是
>   FBO 重绑 + `copyTexSubImage2D`）。
>
> v2 与 v4 的差别正好说明为什么"砍掉 mip"必须配一层缓存才能成立：v2 砍掉 mip 后让
> **每个像素每帧**去 level 0 大跨度采样，v4 砍掉 mip 后让**每个像素每次重绘**采样一次，
> 而重绘在静止和编辑时是不发生的。

### 3.4 验证

桌面 GL（`?mode=webgl` 强制 WebGL2，无头 Edge + CDP）跑三件事：

| 指标 | v3（4 级 mip + 回拷） | 本版本（显示缓存，无 mip） |
|---|---|---|
| 编辑一笔的 `copyTexSubImage2D` 次数 | 3 | **0** |
| 7 级连续缩放后画面面积（第 1 级 / 最后一级） | 758938 / 60350 px | 759264 / 60380 px |
| `gl.getError()` | 0 | 0 |
| 缩放后是否变透明 | 否 | 否（最小一级 meanRGB 仍为图像色调） |
| 编辑拖动帧时间 p50 / p99 | — | 16.7 / 17.1 ms |
| 连续缩放帧时间 p50 / p99 | — | 16.7 / 16.9 ms |

两组帧时间都贴在 60 Hz 的 vsync 上限（16.7 ms），即测量窗口内没有掉帧。
缩放各级的画面面积与 v3 相差不到 0.1%，说明新架构与旧的 mip 路径视觉等价。

启动日志里这行表示新路径生效：

```
gpu canvas: target Rgba8Unorm, ..., backend Gl, view cache true
```

回退开关：`PHOTOCRAFT_VIEW_CACHE=0` 会让视图跳过缓存、按老方式直接画 tile
（桌面/原生构建可用；wasm 上环境变量不可读，所以恒为开启）。

> **说明**：开发机的 GL 实现复现不了真机故障，上面的数字是"结构正确性 + 桌面不劣化"的验证。
> 真机若仍卡，可查的是缓存有没有被频繁整屏重绘（比如画布矩形每帧都在变），而不是采样次数。

---

## 4. 缺陷：保存、导出与外链无反应

### 4.1 现象

| 现象 | 表现 |
|---|---|
| 「保存 / 另存为 / 导出」点了没反应 | 卡一下（在编码），然后对话框关闭回到主界面，设备上找不到任何文件 |
| 引擎内的「在 GitHub 上查看」点进去回不来 | Web 组件被导航到 GitHub 页面，引擎没了，也没有返回键，只能杀掉应用重开 |

### 4.2 根因

两件事都不是引擎的锅，而是 **Web 版原本依赖浏览器能力，鸿蒙的 Web 组件没有**：

1. **保存与导出**。引擎里 `保存 .pcraft`、`导出 PNG/JPG` 最终都汇到同一个动作
   （`apps/photocraft-web/src/web.rs::download`）：把字节打成 `Blob` → `URL.createObjectURL`
   → 造一个隐藏的 `<a download>` → `click()`。桌面浏览器会弹下载；
   **ArkWeb 不会处理 `<a download>`**，于是这次点击安静地消失 —— 引擎认为写入成功，
   对话框关闭，设备上什么都没有。
2. **外部链接**。egui 的 `open_url` 在 Web 上就是 `window.open(url, "_blank")`。
   Web 组件的 `multiWindowAccess` 默认为 false，于是新窗口变成"在当前 Web 组件里导航"，
   编辑器页面被 GitHub 整页顶掉。

### 4.3 修法

全部在外壳层完成，**没有改动引擎**：

| 位置 | 改动 |
|---|---|
| `rawfile/photocraft/index.html` | 覆写 `URL.createObjectURL` 记住 `blob: URL → Blob` 的映射；覆写 `HTMLAnchorElement.prototype.click`，遇到带 `download` 的 blob 链接就拦下来，把字节按 256 KiB 切片 base64 后经 `pcBridge.beginSave / saveChunk / finishSave` 交给原生 |
| `rawfile/photocraft/index.html` | 覆写 `window.open`，并在 document 上用捕获阶段监听 `click`，把 http(s) 链接一并拦下，交给 `pcBridge.openUrl`；**绝不让它把编辑器页面顶掉** |
| `common/ResourceBridge.ets` | 新增 `beginSave / saveChunk / finishSave`：拼装字节后调 `DocumentViewPicker.save()` 让用户选目录，写完后把完整路径写进 `AppStorage`；选择器不可用时兜底写到应用 `filesDir/exports` |
| `common/ResourceBridge.ets` | 新增 `openUrl`：用 `want`（`ohos.want.action.viewData` + `entity.system.browsable`）拉起系统浏览器 |
| `pages/Index.ets` | 监听 `saveStatus` 弹 toast，告诉用户文件存到了哪；三种形态都加了常驻的「返回编辑器」入口（`controller.loadUrl` 重新加载首页） |
| `pages/Help.ets` | 新增「保存与导出」一节，说明选择器与兜底目录 |

### 4.4 验证

桌面（headless Edge + CDP）跑真实引擎页面，合成一次 1 MB 的 `<a download>` 点击：

```
saves: [{"name":"verify-export.png","mime":"image/png","total":1000000,"got":1000000,"finish":1000000}]
urls:  ["https://github.com/storytold/photocraft", "https://example.com/photocraft"]
href:  http://127.0.0.1:8901/index.html?mode=webgl     ← 页面没有被顶掉
```

即：字节完整送达宿主（分块无损）、两类外链都被接管、编辑器页面保持不动。
原生侧的 `DocumentViewPicker` 落盘路径需要在真机上确认。

---

## 5. 缺陷：开着导航器时编辑极卡

### 5.1 现象

| 现象 | 表现 |
|---|---|
| 笔尖一落到画布上就顿 | 缩小状态描边时持续掉帧；画布本身跟得上，是旁边那块缩略图在拖 |
| 关掉右侧「导航器」面板立刻恢复 | 缩略图跟着笔迹实时刷新，笔尖每动一下它就重画一次 |

### 5.2 根因：缩略图每帧把整幅文档重新合成一遍

`navigator_texture`（`crates/ui-egui/src/canvas.rs`）在 GPU 画布模式下有一条按「文档快照 +
预览键」的缓存，键不变就直接复用纹理。但描边期间这两个键都会变：

1. `display_doc` 在 `LiveStroke` 活跃时返回的是**笔迹自己的那份文档**（`l.stroke.doc`），
   而 `display_key()` 等于「笔迹起始键 + 已画的步数」—— 每移动一次就 +1；
2. 于是缓存每帧失效，每帧都走到 `photocraft_compose::thumbnail_buffer(&doc, 512)`。
   这条路径在本例（3120×2080 = 6.5 MP，低于 16 MP 的代理阈值）没有代理可用，
   等于**把整幅文档所有图层全分辨率合成一遍再面积平均到 512 px**。

CPU 画布模式不受影响：那种模式下面板直接复用画布纹理（`ensure_texture`），不重新合成。

### 5.3 为什么之前的性能验证没抓到

`Panels::default()` 里 `navigator: false` —— **导航器面板默认是关的**。
此前所有帧时间测试都在面板关闭时跑，自然测不到。测试驱动后来加了 `SEED_NAV=1`：
页面加载前把 `panels.navigator = true` 写进 localStorage 的 `photocraft.preferences.panelLayout`。
（不加这个变量时也会**先把存储里的布局重置掉**，否则复用同一个浏览器 profile 时，
上一次留下的开启状态会让"关闭"对照说谎。）

### 5.4 修法

1. **手势期间保持旧图**：画笔/移动/修补/渐变等画布拖拽过程中，面板不重算，松手后再追。
   这是最贵的一项 —— 一条笔画原本要重算整幅上百次。移动和修补本来就是这个策略，
   现在推广到所有画布手势，并顺手堵住了"每笔开头那一帧"（那一步的 damage 是空矩形，
   原逻辑会掉进全量重算）。
2. **松手后按 damage 只重算改动区**：缓存带上 `DocState::revision` 与折叠了显示键的预览键
   （对齐 `CanvasCache`），于是可以直接复用画布路径那套 `damage_since`，
   再用 `render_reduced_damage` + `set_partial` 只更新那一块 —— 与整幅缩小的结果逐像素一致。
   只有整幅会走代理路径（面积 > `PROXY_THUMBNAIL_PIXELS`）时才不用局部，避免两者结果不一致。
3. 每次**全量重算**且文档 ≥ 4 MP 时打一行 `navigator: full reduction of W×H px`。
   编辑过程中出现这行就说明面板还在整幅重算；正常情况下只应在打开文档时出现一次。

> 顺带一个坑：这里原本想按耗时打点（超过 8 ms 才记），结果那行日志根本没进 wasm ——
> `gpu_canvas::now_ms()` 在 wasm 上是**恒返回 0 的桩**（只有原生实现了），
> 于是 `ms = 0.0 - 0.0`、`ms > 8.0` 被编译器证明恒假，整段（连字符串）一起被删掉了。
> 同一原因，`Perf::span` / `Perf::composite_ms` 这类计时在网页和真机上都读 0，
> 只能在桌面原生构建里看。所以真机诊断要用"工作类型"而不是"耗时"。

### 5.5 验证

3120×2080 的 JPEG、缩小到约 10%、同一段画笔拖动（116 步），headless Edge + CDP，
`?mode=webgl`，统计 128~130 帧的 rAF 间隔：

| 场景 | p50 | p90 | p99 | max | mean |
|---|---|---|---|---|---|
| 导航器关闭（对照） | 16.7 | 16.8 | 16.9 | 17.3 | 16.7 ms |
| 导航器开启，修复前 | **166.6** | 183.4 | **200.0** | 216.7 | 103.3 ms |
| 导航器开启，修复后 | 16.7 | 16.8 | 16.9 | 33.3 | 16.8 ms |

修复前每帧多出约 150 ms 的 CPU 合成 —— 桌面上就是 10 倍，平板上只会更差。
修复后开与关的 p50/p90/p99 完全一致，只剩一帧 83 ms（笔画提交那一帧）。
缩放回归（开着导航器连跑 7 级）画面与 `gl.getError()` 均无变化；
缩略图在松手后确实追上了（描边前后对比：缩略图变化区 112×68、209 个像素，
正是那一笔在缩略图上的斜线）。

> **说明**：这里量的是桌面 CPU。真机上同样的合成只会更慢，所以"每帧少 150 ms"是下界。
> 真机若仍顿，先在日志里搜 `navigator: full reduction` —— 编辑时出现就说明面板还在整幅重算
> （正常只应在打开文档时出现一次）。

---

## 6. 重新编译引擎

配方与已知坑全部在 [`tools/build_engine_zh/README.md`](../tools/build_engine_zh/README.md)，
这里只列要点。

### 6.1 需要什么

- Rust `stable` + `wasm32-unknown-unknown` 目标
- `wasm-bindgen-cli 0.2.129`、`binaryen`（`wasm-opt`）
- `fontTools`（生成字体子集）
- Windows 上若没有 MSVC/Windows SDK，可用 `x86_64-pc-windows-gnu` 工具链 + w64devkit（MinGW）
  作为主机工具链；`linker` 侧需补一个 `libgcc_eh.a`（GCC 16 已将其并入 `libgcc.a`，复制一份即可）

### 6.2 一条命令

```bash
bash tools/build_engine_zh/build.sh <上游源码目录> <输出目录>
```

内部使用 `--profile wasm-release`，**不是** `--release`。
把产出的三个文件覆盖 `rawfile/photocraft/`，并确认 `index.html` 顶部的文件名字符串与之对应。

---

## 7. 提交前自查

`build-profile.json5` 一旦在 DevEco 里勾过「自动签名」，就会被写回**本机用户目录下的
绝对路径**与加密口令 —— 这样的版本**不要提交**。
仓库里附了 `tools/check-before-publish.py`，提交前跑一次：

```bash
python tools/check-before-publish.py      # 命中任一项即以退出码 1 结束
```

它扫的是：签名配置目录 `signingConfigs`、`storePassword` / `keyPassword` / `keyAlias`、
证书文件后缀，以及 Windows / macOS / Linux 的**本机绝对路径**（用户目录下的路径）。
命中就手动清掉再提交。
