#!/usr/bin/env bash
# 一次性初始化脚本：git init + Git LFS + 首次提交。
#
# 用法（仓库根目录执行，或任意位置执行都行）：
#     bash tools/init-git-repo.sh
#
# 前提：
#   1. 已安装 Git for Windows（安装时勾选 Git LFS）；
#   2. 已在 GitHub 上建好**空仓库**（不要勾选自动生成 README / LICENSE）；
#   3. 已跑过 python tools/check-before-publish.py 且结果为 OK。
#
# 脚本只做到 commit 为止，push 的命令行会打印出来由你手动执行。

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

command -v git >/dev/null 2>&1 || { echo "未找到 git，请先安装 Git for Windows"; exit 1; }
git lfs version >/dev/null 2>&1 || { echo "未找到 Git LFS，请安装后执行 git lfs install"; exit 1; }

echo "==> 1/5 跑一遍开源前自查"
python tools/check-before-publish.py || python3 tools/check-before-publish.py

echo "==> 2/5 git init + lfs install"
git init -b main
git lfs install

echo "==> 3/5 暂存（.gitattributes 里的 LFS 规则必须在 add 之前生效）"
git add .

echo "==> 4/5 确认 wasm 走的是 LFS"
git lfs ls-files
WASM=$(ls entry/src/main/resources/rawfile/photocraft/*.wasm | head -n1)
SIZE=$(wc -c < "$WASM")
if [ "$SIZE" -lt 100000 ]; then
  echo "!! $WASM 只有 $SIZE 字节，LFS 没生效 —— 先中止，检查 .gitattributes 与 git lfs install"
  exit 1
fi

if ! git config user.email >/dev/null 2>&1; then
  read -rp "git user.name  : " GIT_NAME
  read -rp "git user.email : " GIT_EMAIL
  git config user.name  "$GIT_NAME"
  git config user.email "$GIT_EMAIL"
fi

echo "==> 5/5 首次提交"
git commit -m "$(cat <<'MSG'
feat: PhotoCraft 鸿蒙客户端（HarmonyOS 5+，中文版引擎）

基于上游 storytold/photocraft（MIT / Apache-2.0）的 WebAssembly 版本，
用 ArkWeb 承载并叠加一层自适应原生外壳（2in1 / 平板 / 手机三种形态）。

相对上游引擎的四处改动以补丁形式放在 tools/build_engine_zh/：
- engine-zh.patch    默认语言改 zh-hans、内嵌 Noto Sans SC 子集、接入 egui 字族
- view-cache.patch   去掉文档 mip 链，改为屏幕尺寸离屏 ViewCache + 每帧一次 blit
- navigator.patch    导航器缩略图不再每帧重算整幅文档
- mip-gl-fix.patch   早期版本的 GL mip 反馈环修法（已被 view-cache 取代，保留备查）

原生外壳侧修复：resource:// 下的三层资源读取容错、ESM 胶水层转经典脚本、
保存/导出走 DocumentViewPicker、外链交给系统浏览器。

License: MIT OR Apache-2.0
MSG
)"

echo
echo "提交完成。接下来（把 <远端地址> 换成你在 GitHub 上建的仓库）："
echo
echo "    git remote add origin <远端地址>"
echo "    git push -u origin main"
echo
echo "推送前建议再看一眼将要公开的文件："
echo "    git ls-files | head -n 80"
