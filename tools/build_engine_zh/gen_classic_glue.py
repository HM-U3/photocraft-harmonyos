#!/usr/bin/env python3
"""把 wasm-bindgen 生成的 ESM 胶水层改写成「经典脚本」。

鸿蒙 ArkWeb 的 ES Module 加载器不支持 `resource://` 协议，rawfile 里的
`<name>.js` 用 `import ... from` 会被拒（报
`Failed to fetch dynamically imported module: resource://rawfile/...`）。
改成经典脚本后用 `document.createElement('script') + textContent` 注入即可。

改写是**等价**的，不动任何引擎逻辑：
  1. `export { initSync, __wbg_init as default };`
     -> `window.__PhotoCraftModule = { initSync: initSync, default: __wbg_init };`
  2. `new URL('<name>_bg.wasm', import.meta.url)`
     -> `new URL('<name>_bg.wasm', document.baseURI || 'resource://rawfile/photocraft/')`
  3. 外层包 IIFE + 'use strict'（等价于 ESM 的模块作用域与严格模式）

用法：
    python gen_classic_glue.py <name>.js [<name>.classic.js]
"""

import re
import sys
from pathlib import Path

HEADER = """/*
 * 本文件由 PhotoCraft 的 wasm-bindgen ESM 胶水层自动转换而来（tools/build_engine_zh/gen_classic_glue.py），
 * 仅做「ESM -> 经典脚本」的等价改写，未改动任何引擎逻辑：
 *   1. export { initSync, __wbg_init as default } -> window.__PhotoCraftModule
 *   2. new URL('...wasm', import.meta.url)        -> new URL('...wasm', document.baseURI)
 *   3. 外层包裹 IIFE + 'use strict'（等价于 ESM 的模块作用域与严格模式）
 * 原因：鸿蒙 ArkWeb 的 ES Module 加载器不支持 resource:// 协议。
 * 上游原始文件 {src_name} 保持原样未改动。
 */
"""

EXPORT_RE = re.compile(r"^export\s*\{[^}]*__wbg_init\s+as\s+default[^}]*\}\s*;?\s*$", re.M)
WASM_URL_RE = re.compile(r"new URL\((\s*'[^']*_bg\.wasm'\s*),\s*import\.meta\.url\s*\)")


def convert(src: Path) -> str:
    text = src.read_text(encoding="utf-8")

    if "import.meta.url" not in text:
        raise SystemExit(f"{src}: 没找到 import.meta.url，可能不是 wasm-bindgen 的 ESM 胶水层")

    text, n_url = WASM_URL_RE.subn(
        lambda m: f"new URL({m.group(1)}, (typeof document !== 'undefined' && document.baseURI) "
        "? document.baseURI : 'resource://rawfile/photocraft/')",
        text,
    )
    if n_url == 0:
        raise SystemExit(f"{src}: 没找到 new URL('..._bg.wasm', import.meta.url)")

    text, n_export = EXPORT_RE.subn(
        "window.__PhotoCraftModule = { initSync: initSync, default: __wbg_init };", text
    )
    if n_export == 0:
        raise SystemExit(f"{src}: 没找到 export {{ ... __wbg_init as default }}")

    # 剩下的 import/export 语句说明改写不完整，宁可报错也不要产出半成品。
    leftover = re.findall(r"^\s*(?:import|export)\s", text, re.M)
    if leftover:
        raise SystemExit(f"{src}: 还有 {len(leftover)} 条 import/export 语句未处理")

    # HEADER 里有 `{ initSync, ... }` 这种字面花括号，不能用 str.format，直接替换占位符。
    head = HEADER.replace("{src_name}", src.name)
    return head + "(function () {\n'use strict';\n\n" + text.rstrip() + "\n\n})();\n"


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) == 3 else src.with_suffix(".classic.js")
    dst.write_text(convert(src), encoding="utf-8")
    print(f"{src.name} -> {dst.name}  ({dst.stat().st_size} B)")


if __name__ == "__main__":
    main()
