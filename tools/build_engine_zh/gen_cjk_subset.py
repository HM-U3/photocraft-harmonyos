#!/usr/bin/env python3
"""
Generate `NotoSansSC-Regular-Subset.ttf` for the PhotoCraft web build.

Why this exists
---------------
PhotoCraft's web build embeds its fonts via `include_bytes!` and, on `wasm32`,
`crates/ui-egui/src/cjk_fonts.rs` returns an *empty* list of system CJK fonts
(the browser sandbox cannot enumerate them).  So if the UI is switched to
Simplified Chinese, every Han character renders as blank / tofu unless a CJK
face is embedded into the wasm.

Noto Sans SC full VF is ~17 MB — far too big.  This script instantiates the
variable font at wght=400 and subsets it to exactly the characters the engine's
own i18n catalogs can ever ask for, plus the usual Latin / punctuation ranges.
Result is ~550 KB / ~2350 glyphs.

Usage
-----
    pip install fonttools brotli
    python gen_cjk_subset.py --src <SRC_ROOT> --vf NotoSansSC-VF.ttf --out NotoSansSC-Regular-Subset.ttf

`--src` is the PhotoCraft checkout; all `crates/ui-egui/src/i18n/*.tsv` catalogs
are scanned so that adding a language later automatically widens the subset.

Font: Noto Sans SC — SIL Open Font License 1.1 (`fonts/LICENSE-NotoSansSC.txt`).
"""

import argparse
import glob
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer


# Characters that are safe/necessary to always keep, regardless of catalogs.
EXTRA_RANGES = [
    (0x0020, 0x007E),   # ASCII
    (0x00A0, 0x00FF),   # Latin-1 Supplement
    (0x0100, 0x017F),   # Latin Extended-A
    (0x2000, 0x206F),   # General Punctuation
    (0x2070, 0x209F),   # Super/Subscripts
    (0x20A0, 0x20BF),   # Currency Symbols
    (0x2100, 0x214F),   # Letterlike Symbols
    (0x2190, 0x21FF),   # Arrows
    (0x2200, 0x22FF),   # Mathematical Operators
    (0x2460, 0x24FF),   # Enclosed Alphanumerics
    (0x25A0, 0x25FF),   # Geometric Shapes
    (0x2600, 0x26FF),   # Miscellaneous Symbols
    (0x2700, 0x27BF),   # Dingbats
    (0x3000, 0x303F),   # CJK Symbols and Punctuation
    (0xFF00, 0xFFEF),   # Halfwidth and Fullwidth Forms
]

EXTRA_LITERAL = "℃℉✓✗×÷°±−–—…‘’“”《》〈〉【】〔〕￥"


def collect_chars(src_root: str) -> set:
    chars = set(EXTRA_LITERAL)
    for lo, hi in EXTRA_RANGES:
        chars.update(chr(c) for c in range(lo, hi + 1))

    tsvs = glob.glob(os.path.join(src_root, "crates", "ui-egui", "src", "i18n", "*.tsv"))
    if not tsvs:
        print(f"[warn] no i18n catalogs found under {src_root}/crates/ui-egui/src/i18n", file=sys.stderr)
    for path in tsvs:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                # catalogs are `key<TAB>value`; fall back to the whole line
                if "\t" in line:
                    line = line.split("\t", 1)[1]
                chars.update(line)
    return chars


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="PhotoCraft source checkout root")
    ap.add_argument("--vf", required=True, help="NotoSansSC-VF.ttf (variable font)")
    ap.add_argument("--out", required=True, help="output subset TTF path")
    ap.add_argument("--wght", type=float, default=400.0)
    args = ap.parse_args()

    chars = collect_chars(args.src)
    print(f"[1/3] character set: {len(chars)} unique chars")

    print(f"[2/3] instantiating VF at wght={args.wght:g} ...")
    vf = TTFont(args.vf)
    static = instancer.instantiateVariableFont(vf, {"wght": args.wght}, inplace=False, updateFontNames=True)

    tmp = os.path.splitext(args.out)[0] + "._tmp_static.ttf"
    static.save(tmp)

    print("[3/3] subsetting ...")
    font = TTFont(tmp)
    opts = subset.Options()
    opts.layout_features = ["*"]          # keep GSUB/GPOS so punctuation kerning still works
    opts.notdef_outline = True
    opts.recommended_glyphs = True
    opts.drop_tables += ["DSIG"]
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.name_languages = ["*"]
    sub = subset.Subsetter(options=opts)
    sub.populate(unicodes=[ord(c) for c in chars])
    sub.subset(font)
    font.save(args.out)

    n_glyphs = len(font.getGlyphOrder())
    n_han = sum(1 for c in chars if 0x4E00 <= ord(c) <= 0x9FFF)
    size = os.path.getsize(args.out)
    print(f"done: {args.out}")
    print(f"      {size:,} bytes ({size / 1024:.0f} KiB), {n_glyphs} glyphs, {n_han} Han chars")
    try:
        os.remove(tmp)
    except OSError as e:
        print(f"[note] leftover temp file {tmp} ({e})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
