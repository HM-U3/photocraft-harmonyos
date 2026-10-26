# 引擎交叉编译（原生 .so）

`entry/libs/arm64-v8a/libphotocraft_native.so` 是上游 PhotoCraft 的 Rust 源码加上鸿蒙移植后，
用 OHOS NDK 交叉编译出来的产物。**它不进版本库**（release 约 74 MB），
所以 clone 之后要自己编一次才能装机运行。

## 1. 准备

| 需要 | 说明 |
|---|---|
| 上游源码 | [storytold/photocraft](https://github.com/storytold/photocraft) 的 Cargo workspace，外加本工程的移植改动（见 §3） |
| Rust | `rustup target add aarch64-unknown-linux-ohos`（脚本会检查并补装） |
| OHOS NDK | DevEco Studio 自带的 `sdk/default/openharmony/native` |

**SDK 路径不要带空格。** `D:/DevEco Studio/sdk` 里的空格会让 cc-rs 把
`--sysroot` 参数切碎，报一连串「头文件找不到」。先做一个无空格的入口再指过去：

```bat
cmd /c mklink /J D:\ohsdk "D:\DevEco Studio\sdk"
```

```bash
export OHOS_SDK="D:/ohsdk/default/openharmony"
```

## 2. 编译并投放

```bash
bash tools/build_engine_native/build_ohos.sh /d/pcbuild/photocraft --hap
```

不加 `--app` 时默认投放到本仓库；`--hap` 会顺带跑 `hvigor assembleHap`。

脚本做的事其实就是下面这几条环境变量 + 一次 cargo build，想手动跑也一样：

```bash
export OHOS_NDK_HOME="$OHOS_SDK"
export NDK="$OHOS_SDK/native"
export CC_aarch64_unknown_linux_ohos="$NDK/llvm/bin/clang"
export AR_aarch64_unknown_linux_ohos="$NDK/llvm/bin/llvm-ar"
export CXX_aarch64_unknown_linux_ohos="$NDK/llvm/bin/clang++"
export CFLAGS_aarch64_unknown_linux_ohos="--sysroot=$NDK/sysroot -D__MUSL__"

cargo build -p photocraft-ohos --release --target aarch64-unknown-linux-ohos
```

`-D__MUSL__` 不能省：OHOS 的 libc 是 musl 派生，缺这个宏时部分 C 依赖会走 glibc 分支。

release 全量编译约 16 分钟（首次），增量通常 1~3 分钟。

## 3. 移植改动清单

相对上游的改动集中在三处，都不改变上游功能：

### 3.1 `apps/photocraft-ohos`（新增）

NAPI 宿主 crate，`crate-type = ["cdylib"]`，产物名 `libphotocraft_native.so`：

- 渲染线程：`OH_NativeWindow` → `wgpu::Surface`（`Backends::GL`）→ `ctx.run_ui` 循环；
- 输入队列：触摸 / 鼠标 / 键盘 / 滚轮 / IME 各入口都是「压进 `Mutex<Vec<InputEvent>>`」，
  渲染线程每帧取空，NAPI 调用不阻塞；
- 平台请求队列：引擎要弹文件对话框或打开外链时排进 `REQUESTS`，由 ArkTS 轮询取走；
- 系统字体：探测 `/system/fonts` 下的 CJK 字体，注册为最低优先级回退。

导出给 ArkTS 的函数（`@ohos.d.ts` 里同名）：

```
start(surfaceId, w, h, dpi)  stop()  resize(w, h, dpi)  isRunning()
touch(phase, x, y)  mouse(phase, button, x, y)  wheel(dx, dy, ctrl, shift, alt)
key(phase, code, ctrl, shift, alt, text)  imeText(text)  imeBackspace(n)  wantsTextInput()
setDataDir(dir)  takeRequests()  openFile(name, buffer)  exportPng()
```

### 3.2 `crates/ui-egui`（可脱离 eframe）

所有 `eframe::Frame` 的使用收进 `#[cfg(feature = "eframe")]`，
宿主入口变成 `logic_frame(ctx)` / `ui_frame(ui)` / `raw_input_frame(ctx, &mut raw)`。
`photocraft-ohos` 以 `default-features = false` 依赖它。

顺带两处必须注意：

- 鸿蒙上 `target_os` 上报为 `linux` 但没有 winit，所以「有没有事件循环」的判断要三态
  （`eframe` / 桌面 `linux` / 独立宿主），不能只判 `target_os`；
- `cpu_prev` 之类的遥测在独立宿主里没有数据源，传 `None` 而不是 `Some(0.0)`。

### 3.3 平台服务

文件读写、保存导出、外链打开改成「请求 → 宿主代理」的实现，
桌面构建仍走原来的原生对话框。

## 4. 常见坑

| 现象 | 原因 / 处理 |
|---|---|
| `cargo` 卡在解析依赖不往下走 | `?rev=<sha>` 形式的 git 依赖会按 SHA 单独 fetch，国内经常永久卡住。改用「浅克隆对应分支 → deepen → `git clone --bare` 灌进 `~/.cargo/git/db/<name>-<hash>`」 |
| `--sysroot` 被切碎、头文件找不到 | SDK 路径含空格，见 §1 |
| `undefined reference to ...` 一堆 C 符号 | 少了 `-D__MUSL__` |
| 编到一半 `cc` 报 `unrecognized argument` | `CC_aarch64_unknown_linux_ohos` 指到了 win 的 clang，要用 NDK 里的 |
| 装机后启动即失败 | 先确认 `entry/libs/arm64-v8a/` 里真有 `.so`（`**/libs/` 被 gitignore 了） |

## 5. 历史

1.x 时期引擎是 `photocraft-web` 编出的 WebAssembly（24.5 MB）+ ArkWeb 加载，
那套配方（中文化补丁、字体子集、wasm-bindgen 流程）仍留在
[`../build_engine_zh/`](../build_engine_zh/) 存档，**2.0 起不再适用**。
