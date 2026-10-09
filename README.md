# 照片工坊 · PhotoCraft for HarmonyOS

> 把开源图像编辑器 **[PhotoCraft](https://github.com/storytold/photocraft)**（Rust → WebAssembly）装进
> **HarmonyOS 5+** 的客户端。引擎跑在 ArkWeb 里，外面套一层原生鸿蒙外壳 ——
> 鸿蒙平板与鸿蒙电脑（2in1）都可用，界面已完整中文化。

<p align="center">
  <img src="docs/images/main-window.png" alt="照片工坊在鸿蒙电脑上的主界面" width="900">
</p>

<p align="center"><sub>鸿蒙电脑（2in1）上的主界面 · 引擎与外壳均已中文化</sub></p>

---

## 一、这是什么

- **上游**：PhotoCraft 是一个用 Rust 编写的开源图像编辑器，通过 `egui` + `wgpu` 渲染，
  编译成 WebAssembly 后在浏览器中运行；功能面向 Photoshop 类工作流（图层、选区、路径、滤镜等）。
  上游目前仍处于 **early alpha**。
- **本工程**：把它移植到鸿蒙。Web 组件（ArkWeb）负责加载并运行引擎，原生 ArkTS 提供
  侧栏 / 顶栏 / 底栏、渲染后端切换、保存与导出、外部链接处理、内置使用说明等能力。
- **中文化**：不止是外壳。引擎是从上游源码**重新编译**的 —— 默认加载官方简体中文语言包
  （`zh-hans`）并内嵌中文字体，编辑器内部的菜单、工具名与提示同样是中文。

> ⚠️ **非官方适配**
>
> 本工程与上游 PhotoCraft / ArtCraft 团队**没有隶属或背书关系**，是第三方移植。
> 上游本身仍是 early alpha（原作者对其日常可用度的评估约为 Photoshop 的 25%~35%），
> **请勿用于生产工作流**。

## 二、功能

| 类别 | 说明 |
|---|---|
| 编辑能力 | 图层、选区、画笔、橡皮、填充、渐变、文字、形状、变换、滤镜、路径等，与上游 Web 版一致 |
| 文件 | 新建 / 打开 `.pcraft` 文档；可导入 PNG、JPG 以及 PSD（栅格化） |
| 保存导出 | 调用系统「保存到」选择器，保存完成后提示完整文件路径 |
| 渲染后端 | 应用内切换 自动 / WebGL2 / WebGPU / CPU，选择结果持久化 |
| 输入方式 | 鼠标、触摸、手写笔（可用压感控制笔刷大小与不透明度） |
| 界面语言 | 默认简体中文，可在引擎「首选项 › 界面 › 语言」切回英文等其它语言 |

## 三、界面适配

界面随窗口宽度自动切换形态，拖拽窗口实时生效：

| 形态 | 判定条件 | 原生外壳 |
|---|---|---|
| 鸿蒙电脑 / 二合一（2in1） | 窗口宽 ≥ 840vp | 左侧竖向侧栏（展开 216vp，收起为 64vp 图标条） |
| 鸿蒙平板 | 600vp ≤ 宽 < 840vp | 顶部工具栏（48vp） |
| 鸿蒙手机 / 小窗 | 宽 < 600vp | 底部悬浮胶囊按钮组 |

编辑区始终是**同一个 Web 组件实例**，切换形态只改变其内边距 ——
不会因为拖动窗口而重新加载二十多 MB 的引擎。

## 四、环境要求

| 项 | 要求 |
|---|---|
| 目标系统 | HarmonyOS 5.0（API 12）及以上 |
| 设备类型 | `phone` / `tablet` / `2in1` |
| 开发工具 | DevEco Studio 6.1.1（hvigor 6.24.4 下验证通过） |
| 第三方依赖 | 无，`oh-package.json5` 为空，Sync 不需要联网装包 |
| 必装工具 | **Git LFS** |

> 引擎本体 `.wasm` 约 24.5 MB，使用 **Git LFS** 存储。
> 没装 LFS 直接 clone 只会拿到几百字节的指针文件，装到设备上会一直停在加载页。

## 五、快速开始

### 1. 获取代码

```bash
git lfs install                 # 每台机器只需执行一次
git clone https://github.com/HM-U3/photocraft-harmonyos.git photo
cd photo
git lfs pull                    # 已经 clone 过、想补齐大文件时执行

# 确认是真正的引擎而不是 LFS 指针（应显示约 24.5 MB）
ls -l entry/src/main/resources/rawfile/photocraft/*.wasm
```

不想用 LFS 也可以自己编译引擎，产物完全一致，见
[`tools/build_engine_zh/README.md`](tools/build_engine_zh/README.md)。

### 2. 用 DevEco Studio 打开

1. `File → Open…`，选择**本仓库目录本身**（不要选它的父目录）。
2. 首次打开 IDE 会自动 Sync 一次；本工程无第三方依赖，不需要联网装包。
3. 配置签名（仅首次，用于安装到真机或模拟器）：
   `File → Project Structure → Signing Configs` → 勾选 **Automatically generate signature**
   → 登录华为账号 → `Apply`。IDE 会把 `signingConfig` 写回 `build-profile.json5`。
4. 选择设备（系统需 **HarmonyOS 5.0 / API 12 及以上**），点击 ▶ Run。

> 只做编译验证的话：`Build → Build Hap(s)/APP(s) → Build Hap(s)`，不配签名也能产出 HAP。

### 3. 命令行构建（可选）

```bash
export DEVECO_SDK_HOME="D:\\DevEco Studio\\sdk"
"D:\\DevEco Studio\\tools\\node\\node.exe" \
  "D:\\DevEco Studio\\tools\\hvigor\\bin\\hvigorw.js" \
  assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug --no-daemon
```

## 六、目录结构

```
photocraft-harmonyos/
├── AppScope/                            应用级配置（bundleName / 版本 / 图标）
├── entry/                               主模块（HAP）
│   └── src/main/
│       ├── module.json5                 deviceTypes: phone / tablet / 2in1
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets   入口：状态初始化、页面加载、窗口尺寸监听
│       │   ├── common/Constants.ets            常量与渲染后端枚举
│       │   ├── common/ResourceBridge.ets       javaScriptProxy 桥（配置下发 / 状态回调 / 资源兜底 / 保存 / 外链）
│       │   ├── pages/Index.ets                 主页面：ArkWeb + 自适应原生外壳
│       │   └── pages/Help.ets                  内置「使用说明」页
│       └── resources/
│           ├── base/media/                     应用图标（分层图）与界面 SVG 图标
│           ├── dark/element/color.json         深色主题色
│           └── rawfile/photocraft/             ← 引擎资源
│               ├── index.html                       已改写：加载容错 + 进度 + 错误页
│               ├── photocraft-web-zh.classic.js     经典脚本胶水层（鸿蒙实际加载的）
│               ├── photocraft-web-zh.js             上游 ESM 胶水层（保留备查）
│               └── photocraft-web-zh_bg.wasm        中文引擎本体（约 24.5 MB，Git LFS）
├── tools/
│   ├── build_engine_zh/                 引擎重编译配方（不参与打包）
│   │   ├── README.md                    完整步骤 + 已知坑
│   │   ├── build.sh                     cargo → wasm-bindgen → wasm-opt → 落盘
│   │   ├── gen_classic_glue.py          ESM 胶水层 → 经典脚本
│   │   ├── gen_cjk_subset.py            Noto Sans SC 子集化
│   │   ├── engine-zh.patch              相对上游的全部改动
│   │   ├── mip-gl-fix.patch             仅 GL mip 链那一处，便于单独向上游提交
│   │   ├── view-cache.patch             显示缓存重构
│   │   ├── navigator.patch              导航器缩略图局部重绘
│   │   └── fonts/LICENSE-NotoSansSC.txt Noto Sans SC 的 OFL 1.1 许可
│   └── check-before-publish.py          提交前自查（签名路径、口令、本机绝对路径）
├── docs/
│   ├── images/main-window.png           界面截图
│   └── technical-notes.md               技术细节、根因分析与验证数据
├── LICENSE-MIT / LICENSE-APACHE
├── NOTICE
└── build-profile.json5 / hvigorfile.ts / oh-package.json5 / code-linter.json5
```

## 七、渲染后端

可用后端由系统 Web 内核决定。可在应用内切换，设置会被持久化：

| 后端 | 说明 |
|---|---|
| 自动（默认） | 优先 WebGPU，不可用时回落到 WebGL2 |
| WebGL2 | 兼容性最好，平板与手机推荐 |
| WebGPU | 性能最佳，需要系统与驱动支持 |
| CPU 软件渲染 | 最慢，仅用于排查图形问题 |

切换入口在侧栏 / 顶栏 / 底栏的「渲染后端」，选择后引擎自动重启。

## 八、实现要点

移植过程中主要解决的是「浏览器里能跑、鸿蒙 Web 组件里跑不起来」这一类差异。简单说：

1. **引擎加载三层容错** —— `resource://rawfile` 协议下各设备对 `fetch` / `XHR` 的支持不一致，
   页面依次尝试 `fetch` → `XMLHttpRequest` → 原生分块通道（ArkTS 读 rawfile 后按 1 MiB base64 回传）。
   三层都失败时显示错误详情，并提供「重新加载 / 改用 WebGL2」入口。
2. **胶水层改用经典脚本** —— ArkWeb 的 ES Module 加载器不支持 `resource://`，
   于是把 `wasm-bindgen` 的 ESM 胶水层等价转换成经典脚本内联注入，不改动引擎逻辑。
3. **渲染后端如何真正生效** —— 引擎在 wgpu 内部依据 `navigator.gpu` 是否存在选择后端，
   因此选择 WebGL2 时页面会在初始化前抹掉 `navigator.gpu`，这是该选项能落到引擎上的唯一手段。
4. **屏幕尺寸显示缓存** —— 缩小时原本每帧都要沿 mip 链重采样，在 GL 后端还会触发
   未定义行为导致画面变透明。现改为：文档纹理不再生成 mip，另存一层屏幕尺寸的离屏缓存，
   每帧只做一次 blit；视图与文档都没动时完全不重绘，编辑时只重绘损伤矩形。
5. **导航器缩略图局部重绘** —— 描边期间缩略图原本每帧把整幅文档重新合成一遍，
   是编辑卡顿的主要来源；现在手势期间保持旧图，松手后按损伤矩形局部更新。
6. **保存 / 导出与外链** —— 引擎原本依赖浏览器的 `<a download>` 与 `window.open`，
   ArkWeb 两者都不处理。现在由 `index.html` 拦下并转交原生：保存走系统选择器，
   外链交给系统浏览器，编辑器页面不会被顶掉。

上述每一条的**现象、根因、验证数据**都在 [`docs/technical-notes.md`](docs/technical-notes.md)。

## 九、已知限制

- 上游是 early alpha，功能完整度与稳定性以上游为准；崩溃请先确认在上游 Web 版是否同样出现。
- **CPU 软件渲染**极慢，仅作图形问题排查之用。
- 非中文语言依赖系统字体；Web 环境读不到系统 CJK 字体，因此英文界面正常，其它语言可能出现空白。
- 内嵌中文字体是 **Noto Sans SC** 的子集（属 OFL 1.1 定义的「修改版」），
  而该字体的名称是保留字体名 —— 严格合规需要在**发布二进制**前改名并重编译引擎。
  只发布源码不受影响，详见 [`NOTICE`](NOTICE)。
- 手机形态（< 600vp）已适配但测试较少；主要验证环境是鸿蒙平板与鸿蒙电脑。
- 启动失败时优先在应用内切换渲染后端；日志可在 DevEco 的 Log 面板搜 `[PhotoCraft]` 查看。

## 十、许可与署名

- 本工程沿用上游的 **MIT / Apache-2.0 双许可**（二选一）：
  [`LICENSE-MIT`](LICENSE-MIT) 、 [`LICENSE-APACHE`](LICENSE-APACHE)。
  第三方署名、改动清单与字体声明见 [`NOTICE`](NOTICE)。
- 上游 [PhotoCraft](https://github.com/storytold/photocraft) 同为 MIT / Apache-2.0 双许可。
- `PhotoCraft` / `ArtCraft` 名称与标识为上游团队的商标，本工程仅作非商业性适配使用。
- `rawfile/photocraft/` 下的引擎本体（`.wasm` / `.js`）是**从上游 Rust 源码重新编译**的产物，
  相对上游源码只做了最小改动（默认语言、内嵌中文字体、GL 后端渲染路径），
  补丁见 `tools/build_engine_zh/*.patch`。
- `index.html` 为适配鸿蒙改写了加载逻辑，未改动引擎内部行为。
- 中文字体 **Noto Sans SC**（SIL Open Font License 1.1）以子集形式内嵌，
  许可原文见 `tools/build_engine_zh/fonts/LICENSE-NotoSansSC.txt`。

## 十一、致谢

- [storytold/photocraft](https://github.com/storytold/photocraft) —— 上游引擎
- [egui](https://github.com/emilk/egui) / [wgpu](https://github.com/gfx-rs/wgpu) / [wasm-bindgen](https://github.com/rustwasm/wasm-bindgen) —— 引擎所依赖的生态
- **Noto Sans SC** —— Google，SIL Open Font License 1.1
