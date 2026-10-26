#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""开源前自查：确认仓库里没有签名材料、本机绝对路径等不该公开的东西。

用法：
    python tools/check-before-publish.py [目录]     # 默认检查仓库根目录

命中任一项则以退出码 1 结束，并打印命中的文件与行号。
建议挂到 pre-commit：
    cp tools/check-before-publish.py .git/hooks/    # 或自行在 pre-commit 里调用
"""

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent

# 需要跳过的目录（构建产物 / IDE 缓存 / 本地签名快照）
# .local-signing 是 tools/local-signing.py 存签名原件的地方，已在 .gitignore 里，
# 它本来就装着这些路径与口令，不是泄露。
SKIP_DIRS = {
    ".git", ".hvigor", ".idea", "build", "node_modules", "oh_modules",
    ".clangd", ".local-signing",
}

# (规则名, 正则)
RULES = [
    ("签名文件路径", re.compile(r"\.ohos[\\/]config")),
    ("签名口令", re.compile(r"(storePassword|keyPassword|keyAlias)\s*[:=]")),
    ("鸿蒙签名证书", re.compile(r"\.(p12|cer|p7b)\b")),
    ("Windows 用户目录绝对路径", re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s\"']+")),
    ("macOS/Linux 主目录绝对路径", re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+/")),
]

TEXT_SUFFIXES = {
    ".ets", ".ts", ".js", ".json", ".json5", ".html", ".md", ".py", ".sh",
    ".txt", ".patch", ".yml", ".yaml", ".toml", ".gitignore", ".gitattributes",
}


def iter_files(root: Path):
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        yield p


def main() -> int:
    hits = []
    for path in iter_files(ROOT):
        rel = path.relative_to(ROOT)
        # 脚本自身豁免（本文件里就含这些规则名）；.gitignore 里写的是忽略模式，不是真文件
        if rel.as_posix().endswith("tools/check-before-publish.py"):
            continue
        if path.name.startswith(".git"):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in TEXT_SUFFIXES:
            # 无后缀的文件（如 .gitignore）已在集合里放过；其余二进制跳过
            if path.suffix:
                continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for name, rx in RULES:
            for i, line in enumerate(text.splitlines(), 1):
                if rx.search(line):
                    hits.append((rel.as_posix(), i, name, line.strip()[:120]))

    if not hits:
        print("OK：未发现签名材料或本机绝对路径。")
        return 0

    print("发现 %d 处需要清理的内容：\n" % len(hits))
    for f, ln, name, snippet in hits:
        print("  %s:%d  [%s]" % (f, ln, name))
        print("      %s" % snippet)
    print("\n处理办法见 README「开源前自查」。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
