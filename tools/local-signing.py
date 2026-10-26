#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在「能装真机」与「能公开提交」两种 build-profile.json5 之间切换。

DevEco 自动签名会把本机绝对路径与加密口令写进 build-profile.json5 的
signingConfigs 段。那是不能进公开仓库的东西，但本地装机又必须有它，
于是用这个脚本把两态互转，省得每次手工删改：

    python tools/local-signing.py          # 看当前是哪一态
    python tools/local-signing.py off      # 摘掉签名段 → 可以提交/上传（此时构建出的 HAP 未签名）
    python tools/local-signing.py on       # 恢复签名段 → 可以装真机

签名原件保存在 .local-signing/build-profile.signed.json5（已在 .gitignore 里），
所以 `off` 后随时能 `on` 回来；`off` 不会丢东西。
"""

import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "build-profile.json5"
SNAPSHOT = ROOT / ".local-signing" / "build-profile.signed.json5"

# 产品里对签名配置的引用；签名段被摘掉后它指向不存在的配置，hvigor 会报错，必须一起去掉。
# 连同行首缩进和换行一起吃掉，免得在原位置留一行空白。
PRODUCT_SIGN_REF = re.compile(r'\n[ \t]*"signingConfig"\s*:\s*"[^"]*"[ \t]*,?', re.MULTILINE)


def strip_signing(text: str) -> str:
    """把 `"signingConfigs": [ ... ]` 的内容清空为 `[]`，并去掉产品里的引用。"""
    key = '"signingConfigs"'
    i = text.find(key)
    if i < 0:
        raise SystemExit("build-profile.json5 里找不到 signingConfigs 段，无需处理。")
    lb = text.find("[", i + len(key))
    if lb < 0:
        raise SystemExit("signingConfigs 后面没有数组，文件结构不是预期格式。")

    # 从 '[' 起做方括号配对，跳过字符串里的括号与转义。
    depth, j, in_str, esc = 0, lb, False, False
    while j < len(text):
        c = text[j]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                break
        j += 1
    else:
        raise SystemExit("signingConfigs 的方括号没有闭合，不敢改，请手工检查。")

    text = text[: lb + 1] + text[j:]
    return PRODUCT_SIGN_REF.sub("", text)


def is_public(text: str) -> bool:
    return re.search(r'"signingConfigs"\s*:\s*\[\s*\]', text) is not None


def main() -> int:
    action = (sys.argv[1] if len(sys.argv) > 1 else "status").lower()
    if action not in {"on", "off", "status"}:
        print(__doc__)
        return 2
    if not TARGET.exists():
        raise SystemExit("找不到 %s" % TARGET)

    current = TARGET.read_text(encoding="utf-8")

    if action == "status":
        state = "公开态（无签名，构建出的 HAP 未签名）" if is_public(current) else "本地态（含签名，可装真机）"
        print("build-profile.json5：%s" % state)
        print("签名快照：%s" % ("有 → %s" % SNAPSHOT if SNAPSHOT.exists() else "无"))
        return 0

    if action == "off":
        if is_public(current):
            print("已经是公开态，无需再摘。")
            return 0
        SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(TARGET, SNAPSHOT)
        TARGET.write_text(strip_signing(current), encoding="utf-8", newline="\n")
        print("已摘掉签名段 → 可以提交/上传。")
        print("  签名快照：%s" % SNAPSHOT)
        print("  装真机前记得跑：python tools/local-signing.py on")
        return 0

    # on
    if not SNAPSHOT.exists():
        raise SystemExit(
            "没有签名快照 %s，无法恢复。\n"
            "请在 DevEco 里 File > Project Structure > Signing Configs 勾选自动签名，"
            "让 IDE 写回签名段后再跑一次 off/on 建立快照。" % SNAPSHOT
        )
    shutil.copy2(SNAPSHOT, TARGET)
    print("已恢复签名段 → 可以装真机。")
    print("  提交/上传前记得跑：python tools/local-signing.py off")
    return 0


if __name__ == "__main__":
    sys.exit(main())
