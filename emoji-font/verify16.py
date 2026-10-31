#!/usr/bin/env python3
"""Verify the rebuilt emoji font: structure, ligature coverage, rendering."""
import json, sys
from fontTools.ttLib import TTFont
import uharfbuzz as hb

PATH = sys.argv[1] if len(sys.argv) > 1 else "/root/work/emoji/NotoColorEmoji_new.ttf"

f = TTFont(PATH, lazy=True)
print("tables:", " ".join(sorted(f.keys())))
print("glyphs:", f["maxp"].numGlyphs, "cmap:", len(f.getBestCmap()))
print("upem:", f["head"].unitsPerEm)

strikes = f["CBLC"].strikes
print("strikes:", len(strikes))
for i, s in enumerate(strikes):
    b = s.bitmapSizeTable
    n = b.endGlyphIndex - b.startGlyphIndex + 1
    # sample one bitmap size
    name = f.getGlyphOrder()[b.startGlyphIndex]
    g = f["CBDT"].strikeData[i].get(name)
    dim = (g.metrics.width, g.metrics.height) if g else None
    print(f"  {i}: ppem={b.ppemX} glyphs={n} sampleBitmap={dim}")

gsub = "GSUB" in f
print("GSUB:", gsub)

# ---------- ligature coverage ----------
data = json.load(open("/root/work/emoji/emoji16.json"))
seqs = []
for e in data:
    if e.get("has_img_apple"):
        seqs.append(e["unified"])
    for sv in (e.get("skin_variations") or {}).values():
        if sv.get("has_img_apple"):
            seqs.append(sv["unified"])

blob = open(PATH, "rb").read()
face = hb.Face(blob)
font = hb.Font(face)
cmap = f.getBestCmap()


def shape(s):
    buf = hb.Buffer()
    buf.add_str(s)
    buf.guess_segment_properties()
    hb.shape(font, buf)
    return len(buf.glyph_infos), [p.x_advance for p in buf.glyph_positions]


total = ok = fail = 0
fails = []
for uni in seqs:
    cps = [int(x, 16) for x in uni.split("-")]
    if len(cps) < 2:
        continue
    # 纯 base+VS16 不需要合成（本来就映射到同一个字形）
    non_vs = [c for c in cps if c not in (0xFE0F, 0xFE0E)]
    if len(non_vs) == 1:
        continue
    total += 1
    s = "".join(chr(c) for c in cps)
    n, adv = shape(s)
    if n <= 1:
        ok += 1
    else:
        fail += 1
        if len(fails) < 15:
            fails.append((uni, n, adv))

print()
print(f"sequences needing ligature: {total}")
print(f"  combined OK : {ok}  ({ok*100//max(total,1)}%)")
print(f"  split       : {fail}")
for x in fails:
    print("   ", x)

# ---------- rendering ----------
try:
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new("RGB", (1000, 420), "white")
    d = ImageDraw.Draw(im)
    for i, size in enumerate((120, 64, 32)):
        ft = ImageFont.truetype(PATH, size)
        y = 30 + i * 130
        d.text((20, y), "😀😂👍🏽👨‍👩‍👧🇨🇳🏳️‍🌈", font=ft, embedded_color=True)
    im.save("/workspace/emoji_new_render.png")
    print("render saved: /workspace/emoji_new_render.png")
except Exception as e:
    print("render failed:", e)
