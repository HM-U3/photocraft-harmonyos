#!/usr/bin/env bash
# 重新编译汉化版引擎（WebAssembly），产出三个 rawfile 文件。
#
#   bash build.sh <上游源码目录> <输出目录>
#
# 例：bash build.sh /d/pcbuild/photocraft /d/pcbuild/webtest
#
# 前置：便携工具链见 README.md「一、准备便携工具链」。本脚本不写系统目录。
set -euo pipefail

SRC=${1:?用法: build.sh <上游源码目录> <输出目录>}
OUT=${2:?用法: build.sh <上游源码目录> <输出目录>}
PC=${PCBUILD:-/d/pcbuild}

export RUSTUP_HOME="$PC/rust/rustup"
export CARGO_HOME="$PC/rust/cargo"
TC="$PC/rust/rustup/toolchains/stable-x86_64-pc-windows-gnu"
# rustup 的 shim 在沙箱里会吞掉子进程输出，直接用工具链里的真 cargo。
export PATH="$PC/bin:$TC/bin:$PC/toolchain/w64devkit/bin:$PC/rust/cargo/bin:$PATH"
CARGO="$TC/bin/cargo.exe"
WASM_BINDGEN="$PC/bin/wasm-bindgen-0.2.129-x86_64-pc-windows-msvc/wasm-bindgen.exe"
WASM_OPT="$PC/bin/binaryen-version_133/bin/wasm-opt.exe"

TARGET=wasm32-unknown-unknown
NAME=photocraft-web-zh
# 必须用上游自定义的 `wasm-release` profile（fat LTO + opt-level "s"），
# 不是 `--release`：后者产出的 wasm 大得多，且与上游发布包的可比性对不上。
PROFILE=wasm-release
REL="$SRC/target/$TARGET/$PROFILE"
STAGE="$PC/out-zh"

mkdir -p "$STAGE" "$OUT"

echo "==> 1/4 cargo build ($TARGET, profile $PROFILE)"
"$CARGO" build --manifest-path "$SRC/Cargo.toml" \
    --target "$TARGET" --profile "$PROFILE" -p photocraft-web --bin photocraft-web 2>&1 | tail -5

echo "==> 2/4 wasm-bindgen（--target web 生成 ESM 胶水层）"
"$WASM_BINDGEN" --target web --out-dir "$STAGE" --out-name photocraft-web \
    "$REL/photocraft-web.wasm" 2>&1 | tail -3

echo "==> 3/4 wasm-opt -Oz"
# binaryen 133 把 --enable-all 改名为 --all-features；普通 -Oz 已足够。
"$WASM_OPT" -Oz "$STAGE/photocraft-web_bg.wasm" -o "$STAGE/$NAME"'_bg.wasm'

echo "==> 4/4 拷贝到输出目录 + 生成经典脚本胶水层"
cp "$STAGE/$NAME"'_bg.wasm' "$OUT/$NAME"'_bg.wasm'
cp "$STAGE/photocraft-web.js" "$OUT/$NAME.js"
python "$(dirname "$0")/gen_classic_glue.py" "$OUT/$NAME.js" "$OUT/$NAME.classic.js"

ls -l "$OUT/$NAME.js" "$OUT/$NAME.classic.js" "$OUT/$NAME"'_bg.wasm'
echo "完成。把这三个文件连同 index.html 一起放进 entry/src/main/resources/rawfile/photocraft/。"
