# 照片工坊（PhotoCraft for HarmonyOS）

基于开源项目 **PhotoCraft**（`storytold/photocraft`，MIT / Apache-2.0）的 Web 版（Rust → WebAssembly）
构建的鸿蒙客户端，面向 **HarmonyOS 5.0 及以上**，适配鸿蒙平板与鸿蒙电脑（2in1）。

> **中文版范围**：应用名、原生外壳（侧栏 / 顶栏 / 底栏、状态、关于、内置「使用说明」）
> 以及**引擎内部的菜单、工具名与提示**均已中文化 —— 引擎取自上游源码重新编译，
> 默认加载官方简体中文语言包（`zh-hans.tsv`）并内嵌 Noto Sans SC 字面子集，
> 详见 [§ 八、中文化说明](#八中文化说明)。

- 上游 Web 版是一个纯静态应用（`index.html` + `wasm-bindgen` 胶水层 + 约 24.5 MB 的 `.wasm`），
  编辑器 UI（egui）与渲染后端（wgpu：WebGPU / WebGL2 / CPU）全部在 WebAssembly 中运行。
- 本工程用 **ArkWeb（Web 组件）** 承载该引擎，并叠加一层原生鸿蒙外壳（自适应侧栏 / 顶栏 / 底栏、
  渲染后端切换、引擎状态、全屏、关于面板等）。

> **⚠️ 非官方说明**：这是第三方适配，与上游 PhotoCraft / ArtCraft **没有隶属或背书关系**。
> 上游自身仍处在 **early alpha**（其官方评估与 Photoshop 的日常可用度约 25%~35%），
> 请勿用于生产工作流。许可与署名见 [§ 六、许可与署名](#六许可与署名)。

---

## 零、获取代码（务必先装 Git LFS）

引擎本体 `photocraft-web-zh_bg.wasm`（约 24.5 MB）用 **Git LFS** 存储。
不装 LFS 直接 clone 只会拿到几百字节的指针文件，装到设备上会一直停在加载页。

```bash
git lfs install                 # 每台机器只需一次
git clone <仓库地址> photo
cd photo
git lfs pull                    # 已 clone 过、想补齐大文件时执行
ls -l entry/src/main/resources/rawfile/photocraft/*.wasm   # 确认不是几百字节
```

不想用 LFS 也可以自己编译引擎（产物完全一致，只是要多花一次构建时间），
见 [`tools/build_engine_zh/README.md`](tools/build_engine_zh/README.md)。

---

## 一、用 DevEco Studio 打开

1. 打开 DevEco Studio（本项目在 **DevEco Studio 6.1.1 / hvigor 6.24.4** 下验证通过）。
2. `File → Open…`，选择本目录 `photo`（**注意：选择 photo 目录本身，不要选它的父目录**）。
3. 首次打开后 IDE 会做一次 Sync（`oh-package.json5` 中无任何第三方依赖，不需要联网装包）。
4. 配置签名（仅首次，用于装到真机/模拟器）：
   `File → Project Structure → Signing Configs`，勾选 **Automatically generate signature**，
   登录华为账号后点击 `Apply`。IDE 会自动把 `signingConfig: "default"` 写回 `build-profile.json5`。
5. 选择设备（真机或模拟器，需 **HarmonyOS 5.0 / API 12 及以上**），点击 ▶ Run。

> 只做“编译验证”的话：`Build → Build Hap(s)/APP(s) → Build Hap(s)`，无需签名即可产出 HAP。

### 命令行编译（可选）

```bash
# 在项目根目录执行
export DEVECO_SDK_HOME="D:\\DevEco Studio\\sdk"
"D:\\DevEco Studio\\tools\\node\\node.exe" \
  "D:\\DevEco Studio\\tools\\hvigor\\bin\\hvigorw.js" \
  assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug --no-daemon
```

---

## 二、目录结构

```
photo/
├── AppScope/
│   ├── app.json5                     # 应用级配置（bundleName / 版本 / 图标）
│   └── resources/base/{element,media}
├── entry/                            # 主模块（HAP）
│   ├── build-profile.json5           # 模块构建配置（stageMode）
│   ├── hvigorfile.ts
│   ├── oh-package.json5
│   ├── obfuscation-rules.txt
│   └── src/main/
│       ├── module.json5              # deviceTypes: phone / tablet / 2in1
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets   # 入口：初始化状态、加载页面、监听窗口尺寸
│       │   ├── common/Constants.ets            # 常量、渲染后端枚举
│       │   ├── common/ResourceBridge.ets       # javaScriptProxy 桥（配置下发 + 状态回调 + 资源兜底）
│       │   ├── pages/Index.ets                 # 主页面：ArkWeb + 自适应原生外壳
│       │   └── pages/Help.ets                  # 使用说明（原生中文页，三种形态均可进入）
│       └── resources/
│           ├── base/element/{string,color,float}.json
│           ├── base/media/                     # 应用图标（分层图）+ 界面 SVG 图标
│           ├── base/profile/main_pages.json
│           ├── dark/element/color.json
│           └── rawfile/photocraft/             # ← 引擎资源（中文版，本地重编译产物）
│               ├── index.html                  #   已改写：加载容错 + 进度 + 错误页
│               ├── photocraft-web-zh.js             #   wasm-bindgen ESM 胶水层
│               ├── photocraft-web-zh.classic.js     #   由上一行等价转换的经典脚本版（鸿蒙用）
│               └── photocraft-web-zh_bg.wasm        #   中文引擎本体（约 24.5 MB）
├── tools/build_engine_zh/            # 引擎重编译配方（不参与打包）
│   ├── README.md                     #   完整步骤 + 已知坑
│   ├── build.sh                      #   一条命令：cargo → wasm-bindgen → wasm-opt → 落盘
│   ├── gen_classic_glue.py           #   ESM 胶水层 → 经典脚本（鸿蒙 ArkWeb 需要）
│   ├── gen_cjk_subset.py             #   Noto Sans SC 子集化
│   ├── engine-zh.patch               #   相对上游的全部四处改动
│   ├── mip-gl-fix.patch              #   仅第四处（WebGL2 mip 链），方便提交上游
│   ├── verify-zoom-fix.png           #   缩放修复的验证证据图
│   └── fonts/LICENSE-NotoSansSC.txt  #   Noto Sans SC 的 OFL 1.1 许可
├── build-profile.json5               # 工程构建配置（compatibleSdkVersion 5.0.0(12)）
├── hvigorfile.ts
├── oh-package.json5
├── code-linter.json5
└── local.properties
```

---

## 三、平台适配说明

| 形态 | 判定条件 | 原生外壳 |
|---|---|---|
| 鸿蒙电脑 / 二合一（2in1） | 窗口宽 ≥ 840vp | 左侧竖向侧栏（可展开为 216vp / 收起为 64vp 图标条） |
| 鸿蒙平板 | 600vp ≤ 窗口宽 < 840vp | 顶部工具栏（48vp），左品牌 + 右操作 |
| 鸿蒙手机 / 小窗 | 窗口宽 < 600vp | 底部悬浮胶囊按钮组（62vp） |

- 窗口尺寸由 `EntryAbility` 通过 `windowSizeChange` 实时监听，换算为 vp 后写入 `AppStorage`，
  界面随窗口拖拽实时切换形态（2in1 上拖窄窗口会自动切到平板/手机布局）。
- `module.json5` 的 `deviceTypes` 同时声明 `phone`、`tablet`、`2in1`。
- 编辑区（Web 组件）始终是**同一个组件实例**，外壳只改变其内边距，避免切换布局时重新加载 24.5 MB 引擎。
- 触控：`index.html` 中 canvas 设置了 `touch-action: none`，触摸/笔/鼠标事件直接交给引擎处理。

## 四、渲染后端

鸿蒙设备上的可用性由系统 Web 内核决定，可在应用内切换（设置会持久化）：

| 后端 | 说明 |
|---|---|
| 自动（默认） | 优先 WebGPU，不可用时回落 WebGL2 |
| WebGL2 | 兼容性最好，平板/手机推荐 |
| WebGPU | 性能最佳，需要系统与驱动支持 |
| CPU 软件渲染 | 最慢，仅用于排查图形问题 |

切换方式：侧栏/顶栏/底栏的「渲染后端」入口 → 选择 → 引擎自动重启。
选择结果由 ArkTS 侧写入 `PersistentStorage`，页面启动时通过注入的 `pcBridge.renderMode()` 读取。

## 五、引擎加载容错

### 5.1 胶水层：为什么不用 ES Module

上游 `index.html` 用 `<script type="module">` + `import` 加载胶水层，但 **ArkWeb 的 ES Module 加载器不支持
`resource://` 协议**，真机上会直接报：

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

### 5.2 资源读取三层容错

`resource://rawfile` 协议下不同设备/版本对 `fetch`、`XHR` 的支持存在差异，因此页面按三层依次尝试：

1. `fetch()` 流式读取（可显示精确进度）；
2. `XMLHttpRequest`（`responseType: 'arraybuffer'`）；
3. **原生分块通道** —— 通过 `javaScriptProxy` 注入的 `pcBridge.assetSize()` / `pcBridge.assetChunk()`
   由 ArkTS 侧用 `resourceManager.getRawFileContentSync()` 读取 rawfile，按 1 MiB 分块以 base64 回传。

任一层成功即可启动引擎；三层全失败时页面会显示错误详情（同时上报给原生侧，原生会给出
「重新加载」/「改用 WebGL2」的操作入口）。

`wasm` 读完后以字节形式交给胶水层（`init({ module_or_path: bytes })`），
**不让胶水层自己去 fetch `resource://` 下的 wasm**，从而绕开同样的协议限制。

### 5.3 渲染后端如何真正生效

引擎在 Rust/wgpu 内部按 `navigator.gpu` 是否存在选择后端。因此选「WebGL2」时，
页面会在初始化前把 `navigator.gpu` 抹掉（`Object.defineProperty(navigator, 'gpu', ...)`），
这是该选项能真正落到引擎上的唯一手段；选项值本身仍由 ArkTS 侧经 `pcBridge.renderMode()` 下发。

页面所有关键步骤都会经 `pcBridge.log()` 写入 hilog，在 DevEco 的 Log 面板搜 `[PhotoCraft]` 可见
（例如 `引擎胶水层：经典脚本通道 OK`、`fetch 失败(...)，尝试 XHR`），便于定位卡在哪一层。

## 六、许可与署名

- 本工程沿用上游的 **MIT / Apache-2.0 双许可**（使用者二选一）：
  [`LICENSE-MIT`](LICENSE-MIT)、[`LICENSE-APACHE`](LICENSE-APACHE)。
  第三方署名、改动清单与字体说明见 [`NOTICE`](NOTICE)。
- 上游 PhotoCraft（`storytold/photocraft`）同为 MIT / Apache-2.0 双许可。
- ArtCraft / PhotoCraft 名称与标识为上游团队的商标，本工程仅作非商业性本地适配使用。
- 内嵌的 `rawfile/photocraft/` 中的引擎本体（`.wasm` / `.js`）是**从上游 Rust 源码重新编译**的产物，
  相对上游源码只做了四处最小改动（默认语言改为 `zh-hans`、注册内嵌中文字体、把该字体追加到
  字族回退链、GL 后端 mip 链改走 scratch 纹理 —— 见 §九），补丁见
  `tools/build_engine_zh/engine-zh.patch`。
- `index.html` 为适配鸿蒙做了加载逻辑改写（三层资源读取容错、进度与错误页、经典脚本通道）。
- 中文字体 **Noto Sans SC**（SIL Open Font License 1.1）以子集形式内嵌，许可证见
  `tools/build_engine_zh/fonts/LICENSE-NotoSansSC.txt`；子集化脚本与字符集来源同目录。

### 6.1 开源前自查

`build-profile.json5` 一旦在 DevEco 里勾过「自动签名」，就会被写回**本机绝对路径**
（`C:\Users\<你>\.ohos\config\…`）与加密口令 —— 这个版本**不要提交**。
仓库里附了 `tools/check-before-publish.py`，提交前跑一次：

```bash
python tools/check-before-publish.py      # 命中任一项就以退出码 1 结束
```

它扫的是：`.ohos/config` 签名路径、`storePassword` / `keyPassword`、`.p12/.cer/.p7b`、
以及 `C:\Users\<用户名>\` 这类本机绝对路径。命中就手动清掉再提交。

### 6.2 字体合规（待办）

内嵌的 Noto Sans SC 是**子集化**产物，属于 OFL 1.1 定义的「修改版」，
而 `Noto Sans SC` 是保留字体名（Reserved Font Name）。严格合规需要在发布二进制前
给它改名（例如 `PhotoCraft Sans SC`）：`crates/text/src/fonts.rs` 里的注册名、
`crates/ui-egui/src/theme.rs` 里的字族名，以及字体自身的 name 表都要一起改。
`NOTICE` 里已标注这一点。

## 七、常见问题

| 现象 | 处理 |
|---|---|
| 打开项目后提示 Signing Config 未配置 | `File → Project Structure → Signing Configs` 勾选自动签名 |
| 提示 deviceTypes 与设备不匹配 | 确认设备系统 ≥ HarmonyOS 5.0（API 12） |
| 启动后停在加载页 | 换用「WebGL2」或「CPU」后端；并在 DevEco 的 Log 面板查看 `[PhotoCraft]` 日志 |
| 平板/电脑上窗口拖拽后界面没有变化 | 确认 `EntryAbility` 正常触发 `windowSizeChange`（Log 中可见） |
| 缩小到 40% 以下时画面变成透明棋盘格 | 已修（§九）；若仍出现，说明装的是旧 HAP，重新构建安装即可 |
| 编辑（尤其缩小时）明显卡顿 | 已修（§9.3）：GL 的 mip 链限到 4 级（原来 11 级），每次笔刷移动的拷贝从 11 次降到 3 次；日志里应看到 `backend Gl, gl mips true (<= 4 levels)`。仍觉得慢可以把 `GL_MIP_LEVELS` 调到 2 或 3 重新编译（代价是缩小时画质更糙） |
| 导出 / 保存点了没反应，不知道存到哪 | 已修（§十）：现在会弹系统「保存到」选择器，并在保存完成后提示完整路径 |
| 点了引擎内的「在 GitHub 上查看」回不来 | 已修（§十）：外链一律交给系统浏览器，编辑器页面不会被顶掉；外壳上另加了常驻的「返回编辑器」 |
| 想调整引擎版本 | 见 `tools/build_engine_zh/README.md`：改完源码补丁后跑 `bash tools/build_engine_zh/build.sh <上游源码目录> <输出目录>`（内部用 `--profile wasm-release`，**不是** `--release`），把产出的三个文件覆盖 `rawfile/photocraft/`，并确认 `index.html` 顶部的文件名字符串与之一致 |
| 想把应用名改回 PhotoCraft | 改 `AppScope/resources/base/element/string.json` 的 `app_name` 与 `entry/.../string.json` 的 `EntryAbility_label` |
| 想在引擎里改回英文 | 引擎内「首选项 › 界面 › 语言」可切回任意语言；不过非中文语言依赖系统字体，Web 版读不到系统 CJK 字体，英文界面显示正常，其他语言可能出现空白 |

## 八、中文化说明

| 部分 | 语言 | 能否改 |
|---|---|---|
| 应用名 / 桌面图标名 | 中文（照片工坊） | 可，改 `string.json` 里的 `app_name`、`EntryAbility_label` |
| 原生外壳（侧栏 / 顶栏 / 底栏、状态灯、错误面板） | 中文 | 可，改 `Index.ets` |
| 内置「使用说明」页 | 中文 | 可，改 `pages/Help.ets` |
| 编辑器内部菜单、工具名、提示 | **中文** | 可，引擎内「首选项 › 界面 › 语言」可切换；默认语言由 `tools/build_engine_zh/engine-zh.patch` 决定 |

### 8.1 为什么不能直接改 wasm

最初拿到的引擎是预编译的 `photocraft-web-*_bg.wasm`（约 26 MB）。在其中检索过：
除了依赖库残留（`naga` 的 GLSL 诊断信息、SVG 属性名）之外，**没有任何语言列表、locale 切换
或 i18n 框架**，`Language` / `zh-CN` 都是误命中。逐一核对上游中文词条后得出的结论是
**二进制原地替换不可行**：

| 指标 | 结果 |
|---|---|
| 中文词条总数 | 2045 |
| 在 v0.2.0 wasm 中根本不存在的词条 | 367（18%） |
| 能定位到 `{ptr, len}` 静态对、可原地改写的 | 393 / 1678 |
| 理论最大原地覆盖率 | 989 / 2045（且其中多数无法定位长度字段） |

即：即便把能改的都改了，仍有超过一半的界面是英文，且改写长度受限（不能变长）。
所以走了**从源码重新编译**这条路。

### 8.2 重编译做了什么

上游其实**自带完整的 i18n 框架**（`crates/ui-egui/src/i18n/`），并有 `zh-hans.tsv`、
`zh-hant.tsv`、`ja.tsv` 等词条表（简体中文 2067 行，术语是教科书式的
文件 / 编辑 / 图像 / 图层 / 文字 / 选择 / 滤镜）。只是简体中文词条表是在 v0.2.0 发布
**之后**才合入的（PR #282），所以发布包里的 wasm 不含中文。

因此相对上游源码只打了四处补丁（`tools/build_engine_zh/engine-zh.patch`；第四处是顺手修掉的
一个 GL 渲染缺陷，见 §九）：

1. **默认语言改为简体中文** —— `crates/engine/src/prefs.rs` 中 `Interface::default()` 的
   `language` 由 `"auto"` 改为 `"zh-hans"`。引擎仍保留完整的语言切换能力，用户可在
   「首选项 › 界面 › 语言」改回任意语言。
2. **内嵌中文字体** —— `crates/text/src/fonts.rs` 增加 `NOTO_SANS_SC` 静态资源并注册到 `BUNDLED`。
   这是必需的一步：上游 web 构建**从不内嵌 CJK 字体**（`cjk_fonts.rs` 在 `wasm32` 下
   返回空列表），也读不到系统字体，没有内嵌字体的话中文会整片渲染为空白/豆腐块。
3. **把中文字体接进 egui 字族** —— `crates/ui-egui/src/theme.rs` 的 `install_fonts_with` 中
   注册 `NotoSansSC`，并追加到 `Proportional` / `Monospace` 两条回退链的末尾（英文仍走原有字体）。

中文字体用 **Noto Sans SC**（OFL 1.1）可变字体在 `wght=400` 处实例化后子集化得到：
**549 KB / 2348 字形**，覆盖引擎全部语言词条表用到的字符 + ASCII + 拉丁扩展 + 标点/箭头/数学
符号 + CJK 标点与全角字符。子集化脚本为 `tools/build_engine_zh/gen_cjk_subset.py`。

产物经 `wasm-opt -Oz` 压缩后约 **24.5 MB**（比原 26 MB 发布包还小），
已在真机同款 Web 内核（Edge + CDP 无头验证）下确认界面完整渲染为中文、无豆腐块，
菜单展开后同样全中文。

### 8.3 重新编译需要什么

不要求改动系统环境，配方全部在 `tools/build_engine_zh/`：

- Rust `stable` + `wasm32-unknown-unknown` 目标、`wasm-bindgen-cli 0.2.129`、`binaryen`（`wasm-opt`）；
- Windows 上若没有 MSVC/Windows SDK，可用 `x86_64-pc-windows-gnu` 工具链 + w64devkit（MinGW）
  作为主机工具链，`linker` 侧需补一个 `libgcc_eh.a`（GCC 16 已将其并入 `libgcc.a`，复制一份即可）；
- `fontTools` 用于生成字体子集。

详细步骤见 `tools/build_engine_zh/README.md`。

### 「使用说明」页

原生页面 `entry/src/main/ets/pages/Help.ets`，已注册到 `main_pages.json`，
在三种形态下都能进入（侧栏条目 / 顶栏图标 / 底栏按钮，或「关于」面板里的按钮），右上角「返回」退出。
内容覆盖：这是什么、首次启动、外壳各项操作、三种形态、渲染后端怎么选、启动失败排查、已知限制、版本与许可。

## 九、已修缺陷：缩小后画面变透明

### 9.1 现象

真机（HarmonyOS 平板，WebGL2 后端）上把图片缩小到大约 **40% 以下**时画面开始变淡，
到 17.8% 时图像区域整片变成**透明棋盘格**，但右侧「导航器」里的缩略图完全正常。

对录屏逐帧量化后确认了阈值（`checker%` = 画布区域里透明棋盘格像素的占比）：

| 缩放 | 46.5% | 42.7% | 32% | 24.8% | 17.8% | 12.9% | 9.1% | 25.5% | 46% |
|---|---|---|---|---|---|---|---|---|---|
| checker% | 2.5 | 2.3 | 3.8 | 14.6 | **26.0** | 14.7 | 7.9 | 16.2 | 2.5 |

（2~3% 是界面本身的底色，不是画布。）再放大回去就恢复 —— 阈值与
`gpu_canvas.rs` 里 `filter_mode()` 的 LOD 计算完全对得上：`scale = zoom × ppi`，
`scale < 1` 时开始按 `-log2(scale)` 采样 mip 链，LOD 越过 1 就进入 mip 1、越过 2 就进入 mip 2。

### 9.2 根因：GL 上的 mip 链反馈环

结论是**采样的 mip level ≥ 1 全为 0**（alpha = 0 → 画布着色器显示透明棋盘格），
mip 0 是好的，所以只要 LOD < 1（缩放够大）就一切正常。

原因在上游的 `crates/ui-egui/src/gpu_canvas.rs::DocTextures::regenerate_mips`：
它逐级生成 mip 链，生成第 `n` 级时**把源（第 `n−1` 级）和渲染目标（第 `n` 级）
放在同一张 GL 纹理上** —— 采样它的同时渲染进它。

- 在 **WebGPU** 上这是合法且有明确定义的（wgpu 保证同一提交内的读写顺序），
  所以桌面浏览器的 Web 版一切正常；
- 在 **OpenGL ES / WebGL2** 上这是未定义行为。wgpu-hal 的 GLES 后端用
  `TEXTURE_BASE_LEVEL` / `TEXTURE_MAX_LEVEL` 把采样范围收窄到单级来"规避"它
  （`wgpu-hal-30.0.1/src/gles/queue.rs:1584`），桌面 ANGLE 会按这个范围判定、放行；
  但移动端 GL 驱动（ANGLE over Vulkan、部分原生 GLES 栈）常常直接把这次 draw 丢掉，
  附件保持 `glTexStorage2D` 时的零值 —— 整级 mip 就变成全透明。

复现差异也印证了这一点：同一版本在桌面（ANGLE/D3D11 **和** SwiftShader 两套 GL 实现）
从 46% 一路缩到 10% 都完全正常，`gl.getError()` 全程为 0，只有真机出问题。

### 9.3 修法（当前版本）：不修 mip 链，改成一层显示缓存

前三版都在问"怎么把这条 mip 链建出来"。第四版换了个问题：**缩小的画面根本不需要每帧重算**。
`crates/ui-egui/src/gpu_canvas.rs` 由此拆成两层：

1. **文档纹理不再有 mip 链**（`mip_level_count = 1`）。反馈环、`GL_MIP_LEVELS`、scratch
   纹理、`copy_texture_to_texture` 全部消失 —— 画面变透明的根因是被**删掉**的，不是绕过去的。
2. **新增一层屏幕尺寸的离屏缓存**（`ViewCache`，格式与屏幕一致所以 blit 无需转换），
   里面是当前视图下画布的最终像素：棋盘格、投影、显示 LUT、32 位预览都已合成进去。
3. **每帧只做一次 blit**：把缓存 1:1 贴到屏幕（1 次采样，无过滤）。
4. **缓存什么时候重绘**：视图没动且文档没动 → 不重绘；编辑了一笔 → 只重绘 damage 在屏幕上
   对应的那块矩形（缩小状态通常几十像素）；缩放、平移、改窗口、换显示 LUT → 整屏重绘一次。
5. **缩小时用什么过滤**：没有 mip，着色器按 `1/scale` 自己在 level 0 上做 n×n 次采样
   （最多 3×3 = 9 taps）。这笔开销只在重绘那一帧付，blit 帧不付。

于是"编辑一笔"的成本从 **3 次 pass + 3 次纹理拷贝** 变成 **1 次小矩形 pass**；
"缩放/平移"的成本从 1 次 mip 采样变成 1 次 box filter，且只在视图变化的那一帧发生。

关键的性质变化：**每帧的采样开销和每次编辑的重建开销被解耦了**。v1/v2 之所以反复失败，
正是因为这二者被绑在同一条 mip 链上 —— 想让重建便宜就得砍链，砍链又让每帧变贵。
缓存层把"多久重算一次"变成一个可以自由选择的量，而不是 mip 链的结构所决定的量。

> **前三版（都已放弃）**
> - **v1「scratch + 完整 11 级链 + 着色器兜底」**：逻辑正确，但用户反馈"编辑变得很卡" ——
>   11 次拷贝 + 每个像素多一次 level 0 大跨度采样（兜底）叠加。
> - **v2「GL 不用 mip 链，着色器在 level 0 上做 2×2 共 4 次采样」**：编辑路径零开销，
>   但比 v1 **更卡** —— 采样从"1 次小纹理"变成"4 次大纹理大跨度采样"，缩小时每个屏幕
>   像素都是 cache miss。
> - **v3「保留链但只建 4 级，GL 上 scratch + 回拷」**：画面正确、拷贝降到 3 次/笔，
>   但每笔仍有 3 次拷贝的固定开销（GL 上没有 `glCopyImageSubData`，一次拷贝是
>   FBO 重绑 + `copyTexSubImage2D`），用户反馈"更加卡了"。
>
> v2 与 v4 的差别正好说明了为什么"砍掉 mip"必须配一层缓存才能成立：v2 砍掉 mip 后让
> **每个像素每帧**去 level 0 大跨度采样，v4 砍掉 mip 后让**每个像素每次重绘**采样一次，
> 而重绘在静止和编辑时是不发生的。

### 9.4 验证

桌面 GL（`?mode=webgl` 强制 WebGL2，无头 Edge + CDP）跑三件事：

| 指标 | v3（4 级 mip + 回拷） | 本版本（显示缓存，无 mip） |
|---|---|---|
| 编辑一笔的 `copyTexSubImage2D` 次数 | 3 | **0** |
| 7 级连续缩放后画面面积（第 1 级 / 最后一级） | 758938 / 60350 px | 759264 / 60380 px |
| `gl.getError()` | 0 | 0 |
| 缩放后是否变透明 | 否 | 否（最小一级 meanRGB 仍为图像色调） |
| 编辑拖动帧时间 p50 / p99 | — | 16.7 / 17.1 ms |
| 连续缩放帧时间 p50 / p99 | — | 16.7 / 16.9 ms |

两组帧时间都贴在 60 Hz 的 vsync 上限上（16.7 ms），即测量窗口内没有掉帧。
缩放各级的画面面积与 v3 相差不到 0.1%，说明新架构与旧的 mip 路径视觉等价。

启动日志里这行表示新路径生效：

```
gpu canvas: target Rgba8Unorm, ..., backend Gl, view cache true
```

回退开关：`PHOTOCRAFT_VIEW_CACHE=0` 会让视图跳过缓存、按老方式直接画 tile（桌面/原生构建
可用；wasm 上环境变量不可读，所以恒为开启）。

> 说明：这台开发机的 GL 实现复现不了真机故障，上面的数字是"结构正确性 + 桌面不劣化"的
> 验证，真机的卡顿是否消失仍需装一次新包确认。真机若仍卡，可查的是缓存有没有被
> 频繁整屏重绘（比如画布矩形每帧都在变），而不是采样次数。

---

## 十、已修缺陷：保存 / 导出没有反应，外链回不来

### 10.1 现象

| 现象 | 表现 |
|---|---|
| 「保存 / 另存为 / 导出」点了没反应 | 卡一下（在编码），然后对话框关闭回到主界面，设备上找不到任何文件 |
| 引擎内的「在 GitHub 上查看」点进去回不来 | Web 组件被导航到 GitHub 页面，引擎没了，也没有返回键，只能杀掉应用重开 |

### 10.2 根因

两件事都不是引擎的锅，而是 **Web 版原本依赖浏览器能力，鸿蒙的 Web 组件没有**：

1. **保存与导出**。引擎里 `保存 .pcraft`、`导出 PNG/JPG` 最终都汇到同一个动作
   （`apps/photocraft-web/src/web.rs::download`）：把字节打成 `Blob` → `URL.createObjectURL`
   → 造一个隐藏的 `<a download>` → `click()`。桌面浏览器会弹下载；
   **ArkWeb 不会处理 `<a download>`**，于是这次点击安静地消失 —— 引擎认为写入成功，
   对话框关闭，设备上什么都没有。

2. **外部链接**。egui 的 `open_url` 在 Web 上就是 `window.open(url, "_blank")`。
   Web 组件的 `multiWindowAccess` 默认为 false，于是新窗口变成"在当前 Web 组件里导航"，
   编辑器页面被 GitHub 整页顶掉。

### 10.3 修法

全部在外壳层完成，**没有改动引擎**：

| 位置 | 改动 |
|---|---|
| `rawfile/photocraft/index.html` | 覆写 `URL.createObjectURL` 记住 `blob: URL → Blob` 的映射；覆写 `HTMLAnchorElement.prototype.click`，遇到带 `download` 的 blob 链接就拦下来，把字节按 256 KiB 切片 base64 后经 `pcBridge.beginSave / saveChunk / finishSave` 交给原生 |
| `rawfile/photocraft/index.html` | 覆写 `window.open`，并在 document 上用捕获阶段监听 `click`，把 http(s) 链接一并拦下，交给 `pcBridge.openUrl`；**绝不让它把编辑器页面顶掉** |
| `common/ResourceBridge.ets` | 新增 `beginSave / saveChunk / finishSave`：拼装字节后调 `DocumentViewPicker.save()` 让用户选目录，写完后把完整路径写进 `AppStorage`；选择器不可用时兜底写到应用 `filesDir/exports` |
| `common/ResourceBridge.ets` | 新增 `openUrl`：用 `want`（`ohos.want.action.viewData` + `entity.system.browsable`）拉起系统浏览器 |
| `pages/Index.ets` | 监听 `saveStatus` 弹 toast，告诉用户文件存到了哪；三种形态都加了常驻的「返回编辑器」入口（`controller.loadUrl` 重新加载首页） |
| `pages/Help.ets` | 新增「保存与导出」一节，说明选择器与兜底目录 |

### 10.4 验证

桌面（headless Edge + CDP）跑真实引擎页面，合成一次 1 MB 的 `<a download>` 点击：

```
saves: [{"name":"verify-export.png","mime":"image/png","total":1000000,"got":1000000,"finish":1000000}]
urls:  ["https://github.com/storytold/photocraft", "https://example.com/photocraft"]
href:  http://127.0.0.1:8901/index.html?mode=webgl     ← 页面没有被顶掉
```

即：字节完整送达宿主（分块无损）、两类外链都被接管、编辑器页面保持不动。
原生侧的 `DocumentViewPicker` 落盘路径需要在真机上确认。

---

## 十一、已修缺陷：开着「导航器」面板时编辑极卡

### 11.1 现象

| 现象 | 表现 |
|---|---|
| 笔尖一落到画布上就顿 | 缩小状态描边时持续掉帧；画布本身跟得上，是旁边那块缩略图在拖 |
| 关掉右侧「导航器」面板立刻恢复 | 缩略图跟着笔迹实时刷新，笔尖每动一下它就重画一次 |

### 11.2 根因：缩略图每帧把整幅文档重新合成一遍

`navigator_texture`（`crates/ui-egui/src/canvas.rs`）在 GPU 画布模式下有一条按「文档快照 +
预览键」的缓存，键不变就直接复用纹理。但描边期间这两个键都会变：

1. `display_doc` 在 `LiveStroke` 活跃时返回的是**笔迹自己的那份文档**（`l.stroke.doc`），
   而 `display_key()` 等于「笔迹起始键 + 已画的步数」——每移动一次就 +1；
2. 于是缓存每帧失效，每帧都走到 `photocraft_compose::thumbnail_buffer(&doc, 512)`。
   这条路径在本例（3120×2080 = 6.5 MP，低于 16 MP 的代理阈值）没有代理可用，
   等于**把整幅文档所有图层全分辨率合成一遍再面积平均到 512 px**。

CPU 画布模式不受影响：那种模式下面板直接复用画布纹理（`ensure_texture`），不重新合成。

### 11.3 为什么之前的性能验证没抓到

`Panels::default()` 里 `navigator: false`——**导航器面板默认是关的**。此前所有帧时间测试都在
面板关闭时跑，自然测不到。现在测试驱动加了 `SEED_NAV=1`：页面加载前把
`panels.navigator = true` 写进 localStorage 的 `photocraft.preferences.panelLayout`。
（不加这个变量时也会**先把存储里的布局重置掉**，否则复用同一个浏览器 profile 时，
上一次留下的开启状态会让"关闭"对照说谎。）

### 11.4 修法

1. **手势期间保持旧图**：画笔/移动/修补/渐变等画布拖拽过程中，面板不重算，松手后再追。
   这是最贵的一项——一条笔画原本要重算整幅上百次。移动和修补本来就是这个策略，
   现在推广到所有画布手势，并顺手堵住了"每笔开头那一帧"（那一步的 damage 是空矩形，
   原逻辑会掉进全量重算）。
2. **松手后按 damage 只重算改动区**：缓存带上 `DocState::revision` 与折叠了显示键的预览键
   （对齐 `CanvasCache`），于是可以直接复用画布路径那套 `damage_since`，
   再用 `render_reduced_damage` + `set_partial` 只更新那一块——与整幅缩小的结果逐像素一致。
   只有整幅会走代理路径（面积 > `PROXY_THUMBNAIL_PIXELS`）时才不用局部，避免两者结果不一致。
3. 每次**全量重算**且文档 ≥ 4 MP 时打一行 `navigator: full reduction of W×H px`。
   编辑过程中出现这行就说明面板还在整幅重算；正常情况下只应在打开文档时出现一次。

> 顺带一个坑：这里原本想按耗时打点（超过 8 ms 才记），结果那行日志根本没进 wasm——
> `gpu_canvas::now_ms()` 在 wasm 上是**恒返回 0 的桩**（只有原生实现了），
> 于是 `ms = 0.0 - 0.0`、`ms > 8.0` 被编译器证明恒假，整段（连字符串）一起被删掉了。
> 同一原因，`Perf::span` / `Perf::composite_ms` 这类计时在网页和真机上都读 0，
> 只能在桌面原生构建里看。所以真机诊断要用"工作类型"而不是"耗时"。

### 11.5 验证

3120×2080 的 JPEG、缩小到约 10%、同一段画笔拖动（116 步），headless Edge + CDP，`?mode=webgl`：
统计 128~130 帧的 rAF 间隔。

| 场景 | p50 | p90 | p99 | max | mean |
|---|---|---|---|---|---|
| 导航器关闭（对照） | 16.7 | 16.8 | 16.9 | 17.3 | 16.7 ms |
| 导航器开启，修复前 | **166.6** | 183.4 | **200.0** | 216.7 | 103.3 ms |
| 导航器开启，修复后 | 16.7 | 16.8 | 16.9 | 33.3 | 16.8 ms |

修复前每帧多出约 150 ms 的 CPU 合成——桌面上就是 10 倍，平板上只会更差。修复后开与关
的 p50/p90/p99 完全一致，只剩一帧 83 ms（笔画提交那一帧）。缩放回归（开着导航器连跑 7 级）
画面与 `gl.getError()` 均无变化；缩略图在松手后确实追上了（描边前后对比：缩略图变化区
112×68、209 个像素，正是那一笔在缩略图上的斜线）。

> 说明：这里量的是桌面 CPU。真机（平板）上同样的合成只会更慢，所以"每帧少 150 ms"是
> 下界。真机若仍顿，先在日志里搜 `navigator: full reduction`——编辑时出现就说明面板还在
> 整幅重算（正常只应在打开文档时出现一次）；没有再查别处。

