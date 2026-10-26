# 中文引擎重编译配方

`entry/src/main/resources/rawfile/photocraft/` 里的 `.wasm` / `.js` **不是**上游发布包里的原文件，
而是从上游 Rust 源码重新编译出来的中文版本。这份配方记录了完整过程，方便以后升级引擎版本时重跑。

> 前提：本目录下的补丁只在**上游 `main` 分支（workspace 版本 0.3.0）**上验证过。
> 上游 0.2.0 发布包里没有 `zh-hans.tsv`（简体中文词条表是 PR #282 之后才合入的），
> 用 0.2.0 源码打这个补丁**不会**得到中文界面。

---

## 0. 背景：为什么不直接改 wasm

见项目根目录 `README.md` § 8.1。一句话：预编译 wasm 里没有 i18n 框架，
逐条原地替换中文字符串的覆盖率不足 50%，且不能改长度 —— 只能重编译。

---

## 1. 准备工具链

以下全部装在 `D:\pcbuild`（示例路径，可换），**不改动任何系统设置 / 注册表**。

### 1.1 Rust

```bash
export RUSTUP_HOME="D:\\pcbuild\\rust\\rustup"
export CARGO_HOME="D:\\pcbuild\\rust\\cargo"
export RUSTUP_DIST_SERVER="https://mirrors.ustc.edu.cn/rust-static"
export RUSTUP_UPDATE_ROOT="https://mirrors.ustc.edu.cn/rust-static/rustup"

rustup-init.exe -y --default-toolchain stable --default-host x86_64-pc-windows-gnu --profile minimal
"$CARGO_HOME/bin/rustup" target add wasm32-unknown-unknown
```

没有 MSVC / Windows SDK 的机器必须选 `x86_64-pc-windows-gnu`（默认 host 是 msvc 会直接编不过）。

### 1.2 MinGW 主机链接器（gnu 工具链需要）

```bash
# w64devkit（免安装，解压即用）；GitHub 慢的话走 https://ghfast.top/ 前缀
# 解压到 D:\pcbuild\toolchain\w64devkit
export PATH="/d/pcbuild/toolchain/w64devkit/bin:$PATH"

# GCC 16 把 libgcc_eh 并进了 libgcc，但 rustc 仍会 -lgcc_eh，补一个副本即可
cp /d/pcbuild/toolchain/w64devkit/lib/gcc/x86_64-w64-mingw32/*/libgcc.a \
   /d/pcbuild/toolchain/w64devkit/lib/gcc/x86_64-w64-mingw32/*/libgcc_eh.a
```

### 1.3 wasm-bindgen-cli 与 binaryen

```bash
# wasm-bindgen-cli 版本必须与 Cargo.lock 里 wasm-bindgen 的版本一致，这里是 0.2.129
# 否则运行时报 "cannot import from module `__wbindgen_placeholder__`"
# binaryen 提供 wasm-opt；binaryen 133 起 `-Oz` 不需要 `--enable-all`（该选项已改名 --all-features）
```

### 1.4 crates.io 镜像

`$CARGO_HOME/config.toml`：

```toml
[source.crates-io]
replace-with = "ustc"
[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
```

### 1.5 环境脚本

把上面的导出写进一个 `env.sh`，每次开工前 `source` 它。**注意**：在某些受限 shell 里
`rustup` 的 shim 会吞掉子进程 stdout（表现为 `cargo --version` 没有任何输出），
直接调用工具链里的真二进制即可：

```bash
export TC="/d/pcbuild/rust/rustup/toolchains/stable-x86_64-pc-windows-gnu"
export CARGO="$TC/bin/cargo.exe"
export RUSTC="$TC/bin/rustc.exe"
```

---

## 2. 拉源码并打补丁

```bash
git clone --depth 1 https://github.com/storytold/photocraft.git D:/pcbuild/photocraft
cd /d/pcbuild/photocraft
git apply <鸿蒙工程>/tools/build_engine_zh/engine-zh.patch
```

补丁做四件事（详见补丁文件内的注释）：

| 文件 | 改动 | 原因 |
|---|---|---|
| `crates/engine/src/prefs.rs` | `Interface::default()` 的 `language`：`"auto"` → `"zh-hans"` | 默认进中文；用户仍可在「首选项 › 界面 › 语言」中改回 |
| `crates/text/src/fonts.rs` | 新增 `NOTO_SANS_SC` 静态资源并加入 `BUNDLED` | 让中文字体能随 `include_bytes!` 编进 wasm |
| `crates/ui-egui/src/theme.rs` | 注册 `NotoSansSC`，并追加到 `Proportional` / `Monospace` 字族回退链末尾 | web 版读不到系统 CJK 字体（`cjk_fonts.rs` 在 `wasm32` 下返回空列表），不内嵌就是整片空白 |
| `crates/ui-egui/src/gpu_canvas.rs` | **渲染架构改为「显示缓存」**：tile 去掉 mip 链（单级），新增屏幕尺寸的离屏 `ViewCache`，每帧只 blit；编辑只重绘 damage 矩形，缩放/平移才整屏重绘 | 修「缩放后画面变透明消失」，同时消除编辑时的每笔重建；详见根目录 `README.md` § 9 |

第 3 条里字体放在**回退链末尾**而不是首位：拉丁字符继续用 Inter / JetBrains Mono 渲染，
只有它们缺字形时才回落到 Noto Sans SC，观感与原版一致。

第 4 条（显示缓存）与中文化无关，是一个独立的**上游缺陷修复**，
单独放在 `view-cache.patch` 里方便提交上游 —— 它同样适用于纯上游代码。
背景与验证见根目录 `README.md` § 9。

第 5 条（导航器节流）同样与中文化无关，单独放在 `navigator.patch`：

| 文件 | 改动 | 原因 |
|---|---|---|
| `crates/ui-egui/src/canvas.rs` | `navigator_texture`：画布手势期间保持旧图、松手后按 `damage_since` + `render_reduced_damage` 只重算改动区；缓存补上 `revision`/预览键以便复用画布那套 damage 机制 | 修「开着导航器面板时编辑极卡」——描边期间缩略图每帧把整幅文档重新合成一遍（6.5 MP 实测每帧 +150 ms）；详见根目录 `README.md` § 11 |

> **`mip-gl-fix.patch` 已废弃**：那是 v3（保留 mip 链、GL 上 scratch + 回拷、只建 4 级）的补丁，
> 已被 `view-cache.patch` 取代。新方案把 mip 链整体删掉，所以那个补丁里针对
> `regenerate_mips` / `GL_MIP_LEVELS` 的改动**不应再应用**。

> **四条反面教训**（都已试过，别再走）：
> - mip 链太长：GLES 没有 `glCopyImageSubData`，一次回拷 = FBO 重绑 + `copy_tex_sub_image_2d`，
>   而**每次笔刷移动都会重建整条链**。11 级 = 11 pass + 11 拷贝/笔刷，真机上直接卡顿。
> - 干脆不要链、改在着色器对 level 0 每次采样：看着省事，实际**更卡** —— 采样从
>   「1 次小纹理」变成「4 次大纹理 cache miss」，而这是**每帧**都要付的。
> - 不要只砍链的长度（v3 的 4 级）：每笔仍有 3 次拷贝的固定开销，用户反馈「更加卡了」。
> - **别信"画布不卡就没事"**：画布的确不卡，卡的是右侧面板。性能测试必须把
>   **导航器面板打开**（`cdp.js` 的 `SEED_NAV=1`）；它默认关闭，所以此前的帧时间测试
>   全部漏掉了它。同理，`now_ms()` 在 wasm 上是恒返回 0 的桩，**计时类的诊断在真机上读 0**，
>   真机只能按"工作类型"打点（如 `navigator: full reduction of …`）。
>
> 前三条合起来说明：**每帧采样开销和每次重建开销被绑在同一条 mip 链上，此消彼长**。
> 只有把它们解耦（采样发生在重绘时，重绘由缓存层决定频率）才能两边都不付。

---

## 3. 生成中文字体子集

```bash
pip install fonttools brotli

# Noto Sans SC 可变字体（OFL 1.1），约 17 MB
python gen_cjk_subset.py \
  --src /d/pcbuild/photocraft \
  --vf  NotoSansSC-VF.ttf \
  --out /d/pcbuild/photocraft/assets/fonts/NotoSansSC-Regular-Subset.ttf
```

脚本会：在 `wght=400` 处实例化可变字体 → 扫描 `crates/ui-egui/src/i18n/*.tsv`
收集所有语言可能出现的字符 → 加上 ASCII / 拉丁扩展 / 标点 / 箭头 / 数学符号 /
CJK 标点 / 全角字符 → 子集化。

当前产物：**549,112 字节（536 KiB），2348 字形，含 1207 个汉字**。

> 新增语言时只要 rerun 一遍即可，脚本按词条表自动扩集。

---

## 4. 编译 + 胶水层 + 落盘（一条命令）

第 4~6 步已经脚本化：

```bash
bash tools/build_engine_zh/build.sh /d/pcbuild/photocraft /d/pcbuild/webtest
```

它依次做：`cargo build --profile wasm-release` → `wasm-bindgen --target web`
→ `wasm-opt -Oz` → 拷贝成 `photocraft-web-zh.{js,classic.js,_bg.wasm}` 到输出目录。
首次约 10 分钟（依赖缓存建好后增量约 5 分钟）。

手动逐条跑的话：

```bash
source /d/pcbuild/env.sh
"$CARGO" build -p photocraft-web --bin photocraft-web \
  --target wasm32-unknown-unknown --profile wasm-release
# 产出 target/wasm32-unknown-unknown/wasm-release/photocraft-web.wasm（约 31.7 MB）

"$WASM_BINDGEN" --target web --out-dir /d/pcbuild/out --out-name photocraft-web \
  /d/pcbuild/photocraft/target/wasm32-unknown-unknown/wasm-release/photocraft-web.wasm

wasm-opt -Oz /d/pcbuild/out/photocraft-web_bg.wasm -o /d/pcbuild/out/photocraft-web-zh_bg.wasm
# 31.7 MB -> 24.5 MB
```

> **profile 必须是 `wasm-release`，不是 `--release`**。上游在 `Cargo.toml` 里为
> 浏览器构建定义了 `[profile.wasm-release]`（fat LTO + `opt-level = "s"`，只有
> `photocraft-raster` / `photocraft-color` 保持 3）。写成 `--release` 不会报错，
> 但产出的是另一套优化配置且会触发一次全量重编译。

---

## 5. 落到鸿蒙工程

`build.sh` 的输出目录里已经有三个最终文件，直接拷进 rawfile：

```bash
RAW=<鸿蒙工程>/entry/src/main/resources/rawfile/photocraft
cp "$OUT/photocraft-web-zh.js"           "$RAW/photocraft-web-zh.js"
cp "$OUT/photocraft-web-zh.classic.js"   "$RAW/photocraft-web-zh.classic.js"
cp "$OUT/photocraft-web-zh_bg.wasm"      "$RAW/photocraft-web-zh_bg.wasm"
```

然后确认 `$RAW/index.html` 顶部三个文件名常量与实际文件名一致：

```js
var JS_CLASSIC_URL = './photocraft-web-zh.classic.js';
var JS_MODULE_URL  = './photocraft-web-zh.js';
var WASM_URL       = './photocraft-web-zh_bg.wasm';
```

`.classic.js` 是必需的 —— ArkWeb 的 ES Module 加载器不支持 `resource://` 协议
（详见根目录 `README.md` § 5.1）。`gen_classic_glue.py` 与 wasm-bindgen 版本无关，
任意版本的 `export { ... }` 列表都能转换；改完 `.js` 后重新生成一次即可：

```bash
python tools/build_engine_zh/gen_classic_glue.py \
  "$RAW/photocraft-web-zh.js" "$RAW/photocraft-web-zh.classic.js"
```

---

## 6. 验证

在 rawfile 目录起一个静态服务器，用无头浏览器（Edge/Chrome + CDP，或 Playwright）打开并截图：

```bash
cd "$RAW" && python -m http.server 8899
# 浏览器打开 http://127.0.0.1:8899/ ，等 canvas 出现后截图
```

判据：

1. 截图里菜单/面板文字是中文，没有 `□` 或空白块（豆腐块 = 字体没内嵌成功）；
2. 点开一个菜单（如「文件」）确认子项也是中文；
3. console 里没有 `Failed to fetch dynamically imported module`。

**缩放回归测试**（改过 `gpu_canvas.rs` 时必须做）：URL 加 `?mode=webgl` 强制走 GL 后端
（不加会走 WebGPU，测试不到 GL 特有问题），拖入一张大图后连续缩小到 10% 左右再放大回去，
每一步截图比对画布区域：

- 图还在（不是整片透明棋盘格）；
- console 里没有 `uncaptured wgpu error`，也没有
  `GPU error ... using the CPU renderer for the rest of the session`
  （出现即意味着已退化为 CPU 渲染，必须查）；
- 引擎日志里 `gpu canvas: ... backend Gl, gl mips true (<= 4 levels)` 说明 GL 路径生效
  （`gl mips false` = 走的 WebGPU，测试不到 GL 特有问题）。

**编辑开销回归**（改过 mip 生成时必须做）：在页面里 hook 一下拷贝调用再画一笔，
数每笔的 `copyTexSubImage2D` 次数 —— 当前应为 **3**（level 1/2/3），原版是 0（原地生成），
改回「完整 11 级链」那版则是 11：

```js
window.__copies = 0; window.__copyLv = [];
const o = WebGL2RenderingContext.prototype.copyTexSubImage2D;
WebGL2RenderingContext.prototype.copyTexSubImage2D = function (t, level) {
  window.__copies++; window.__copyLv.push(level); return o.apply(this, arguments);
};
```

> 验证时务必**在 `$RAW` 目录下起服务**，而不是用 `file://` —— wasm 走 fetch，
> `file://` 下会被 CORS 挡掉。

最后回到工程根目录重新打包：

```bash
cd <鸿蒙工程根目录>
export DEVECO_SDK_HOME="D:\\DevEco Studio\\sdk"
export JAVA_HOME="D:\\DevEco Studio\\jbr"
export PATH="/d/DevEco Studio/jbr/bin:$PATH"
"/d/DevEco Studio/tools/node/node.exe" \
  "/d/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug
```

---

## 7. 已知坑

| 现象 | 原因 / 处理 |
|---|---|
| `cargo` 无任何输出 | rustup shim 在受限 shell 下吞子进程 stdout，直接调 `$TC/bin/cargo.exe` |
| `cannot find -lgcc_eh` | GCC 16 已并入 libgcc，复制一份 `libgcc_eh.a` |
| `linker 'cc' not found` / msvc 报错 | 没装 MSVC，改用 `x86_64-pc-windows-gnu` + w64devkit |
| `Unknown option --enable-all` | binaryen ≥ 133 改名 `--all-features`；直接 `wasm-opt -Oz` 也行 |
| 运行时 `cannot import from module __wbindgen_placeholder__` | wasm-bindgen-cli 与 Cargo.lock 里 wasm-bindgen 版本不一致 |
| 中文全白 / 空白方块 | 忘了第 2 步的 `theme.rs` 补丁，或第 3 步的字体没放进 `assets/fonts/` |
| 编译结果比预期大很多 | 用了 `--release` 而不是 `--profile wasm-release`（见 §4） |
| 缩放后画面变透明消失 | GL mip 链反馈环，见 §2 第 4 条与根目录 `README.md` § 9；改动后务必做 §6 的缩放回归测试 |
| GitHub 下载龟速 | 用 `https://ghfast.top/` 前缀；Rust 走 `mirrors.ustc.edu.cn/rust-static` |
