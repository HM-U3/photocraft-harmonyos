#!/usr/bin/env bash
# 交叉编译鸿蒙原生引擎，并把 libphotocraft_native.so 放进本工程。
#
#   bash tools/build_engine_native/build_ohos.sh <PhotoCraft Rust 源码目录> [选项]
#
# 选项：
#   --app <目录>   要投放 .so 的鸿蒙工程（默认：本仓库根目录）
#   --hap          投放后再跑一次 hvigor assembleHap
#   --debug        编 debug 而不是 release
#
# 环境变量：
#   OHOS_SDK   DevEco SDK 的 openharmony 目录
#              （默认 "D:/DevEco Studio/sdk/default/openharmony"）
#   HVIGOR     hvigorw 路径（默认 "D:/DevEco Studio/tools/hvigor/bin/hvigorw.bat"）
#
# 说明：SDK 路径里带空格会让 cc-rs 把 --sysroot 切碎，报一堆头文件找不到。
# 遇到这种情况先建一个无空格的符号链接/目录联接指向 SDK，再把 OHOS_SDK 指过去，例如
#   cmd /c mklink /J D:\ohsdk "D:\DevEco Studio\sdk"
#   export OHOS_SDK="D:/ohsdk/default/openharmony"
set -euo pipefail

APP="$(cd "$(dirname "$0")/../.." && pwd)"
SRC=""
DO_HAP=0
PROFILE=release

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --hap) DO_HAP=1; shift ;;
    --debug) PROFILE=debug; shift ;;
    -*) echo "未知参数: $1" >&2; exit 2 ;;
    *) SRC="$1"; shift ;;
  esac
done

if [[ -z "$SRC" ]]; then
  echo "用法: bash tools/build_engine_native/build_ohos.sh <PhotoCraft Rust 源码目录> [--hap]" >&2
  exit 2
fi
SRC="$(cd "$SRC" && pwd)"

SDK="${OHOS_SDK:-D:/DevEco Studio/sdk/default/openharmony}"
HVIGOR="${HVIGOR:-D:/DevEco Studio/tools/hvigor/bin/hvigorw.bat}"
TARGET=aarch64-unknown-linux-ohos
NDK="$SDK/native"

if [[ ! -d "$NDK/sysroot" ]]; then
  echo "错误：在 $SDK 下找不到 NDK（native/sysroot）。请设置 OHOS_SDK。" >&2
  exit 1
fi

if ! rustup target list --installed | grep -qx "$TARGET"; then
  echo "==> 安装 Rust 目标 $TARGET"
  rustup target add "$TARGET"
fi

export OHOS_NDK_HOME="$SDK"
export CC_aarch64_unknown_linux_ohos="$NDK/llvm/bin/clang"
export AR_aarch64_unknown_linux_ohos="$NDK/llvm/bin/llvm-ar"
export CXX_aarch64_unknown_linux_ohos="$NDK/llvm/bin/clang++"
export CFLAGS_aarch64_unknown_linux_ohos="--sysroot=$NDK/sysroot -D__MUSL__"

echo "==> cargo build -p photocraft-ohos ($PROFILE, $TARGET)"
cd "$SRC"
if [[ "$PROFILE" == "release" ]]; then
  cargo build -p photocraft-ohos --release --target "$TARGET"
  OUT="$SRC/target/$TARGET/release"
else
  cargo build -p photocraft-ohos --target "$TARGET"
  OUT="$SRC/target/$TARGET/debug"
fi

SO="$OUT/libphotocraft_native.so"
echo "==> 产出 $(wc -c < "$SO") 字节"

DEST="$APP/entry/libs/arm64-v8a"
mkdir -p "$DEST"
cp "$SO" "$DEST/"
echo "==> 已投放 $DEST/libphotocraft_native.so"

if [[ "$DO_HAP" == "1" ]]; then
  echo "==> hvigor assembleHap"
  ( cd "$APP" && DEVECO_SDK_HOME="$(dirname "$SDK")" HOS_SDK_HOME="$(dirname "$SDK")" \
      "$HVIGOR" --mode module -p product=default assembleHap --no-daemon )
fi
