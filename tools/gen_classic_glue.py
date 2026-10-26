# -*- coding: utf-8 -*-
"""
把 wasm-bindgen 的 ESM 胶水层转换成「经典脚本」版本，供鸿蒙 ArkWeb 直接 inline 注入。

背景：ArkWeb 的 ES Module 加载器不支持 resource:// 协议，
      `import('./xxx.js')` 会报 "Failed to fetch dynamically imported module"。
      而经典脚本（<script>textContent</script>）在所有 WebView 里都能跑。

转换只有两处（已逐条校验）：
  1. export { initSync, __wbg_init as default };      ->  window.__PhotoCraftModule = { ... }
  2. new URL('xxx.wasm', import.meta.url)             ->  new URL('xxx.wasm', document.baseURI)
     （import.meta 在经典脚本里是语法错误，必须替换；该分支只在未显式传入 wasm 时才会走到）
  3. 整体包一层 IIFE + 'use strict'，模拟 ESM 的严格模式与模块作用域。

用法: python gen_classic_glue.py <源.js> <输出.js> [wasm文件名]
"""
import io
import os
import re
import sys


def convert(src: str, wasm_name: str) -> str:
    # ---- 前置校验：确认文件结构与预期一致，避免盲改 ----
    if src.count("import.meta") != 1:
        raise SystemExit("预期 import.meta 恰好出现 1 次，实际 %d 次，请人工确认" % src.count("import.meta"))

    export_stmts = re.findall(r"export\s*\{[^}]*\}\s*;", src)
    if len(export_stmts) != 1:
        raise SystemExit("预期恰好 1 条 export {...}，实际 %d 条" % len(export_stmts))
    if "initSync" not in export_stmts[0] or "__wbg_init as default" not in export_stmts[0]:
        raise SystemExit("export 列表与预期不符: %s" % export_stmts[0])

    if re.search(r"^\s*import\s+[\{\'\"]", src, re.M) or re.search(r"^\s*import\s+\*", src, re.M):
        raise SystemExit("发现静态 import 语句，无法直接转为经典脚本")

    out = src

    # 替换 1：import.meta.url -> document.baseURI
    old_url = "new URL('photocraft-web_bg.wasm', import.meta.url)"
    if old_url not in out:
        m = re.search(r"new URL\([^)]*import\.meta\.url\)", out)
        if not m:
            raise SystemExit("未找到 import.meta.url 的使用点")
        old_url = m.group(0)
    new_url = "new URL('%s', (typeof document !== 'undefined' && document.baseURI) ? document.baseURI : 'resource://rawfile/photocraft/')" % wasm_name
    out = out.replace(old_url, new_url)

    # 替换 2：export -> 挂到 window
    out = out.replace(
        export_stmts[0],
        "window.__PhotoCraftModule = { initSync: initSync, default: __wbg_init };"
    )

    header = (
        "/*\n"
        " * 本文件由上游 PhotoCraft 0.2.0 的 wasm-bindgen ESM 胶水层自动转换而来，\n"
        " * 仅做「ESM -> 经典脚本」的等价改写，未改动任何引擎逻辑：\n"
        " *   1. export { initSync, __wbg_init as default } -> window.__PhotoCraftModule\n"
        " *   2. new URL('...wasm', import.meta.url)        -> new URL('...wasm', document.baseURI)\n"
        " *   3. 外层包裹 IIFE + 'use strict'（等价于 ESM 的模块作用域与严格模式）\n"
        " * 原因：鸿蒙 ArkWeb 的 ES Module 加载器不支持 resource:// 协议。\n"
        " * 上游原始文件 photocraft-web-b33881c18c5db349.js 保持原样未改动。\n"
        " */\n"
    )
    body = "(function () {\n'use strict';\n\n" + out.rstrip() + "\n\n})();\n"
    return header + body


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src_path, dst_path = sys.argv[1], sys.argv[2]
    wasm_name = sys.argv[3] if len(sys.argv) > 3 else "photocraft-web-b33881c18c5db349_bg.wasm"

    src = io.open(src_path, encoding="utf-8").read()
    out = convert(src, wasm_name)
    io.open(dst_path, "w", encoding="utf-8", newline="\n").write(out)

    print("源文件   : %s (%d 字节)" % (src_path, len(src.encode("utf-8"))))
    print("输出文件 : %s (%d 字节)" % (dst_path, len(out.encode("utf-8"))))
    print("残留 import.meta : %d" % out.count("import.meta"))
    print("残留 export      : %d" % len(re.findall(r"\bexport\b", out)))
    print("导出入口         : %s" % ("window.__PhotoCraftModule" in out))


if __name__ == "__main__":
    main()
