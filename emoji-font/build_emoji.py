#!/usr/bin/env python3
"""Build a CBDT/CBLC Android-style emoji font from Apple emoji PNGs.

Uses the original 160px Apple PNGs byte-for-byte (no resampling), so the
font stays ~34 MB and keeps the exact artwork.
"""
import json, os, io
from PIL import Image
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.C_B_D_T_ import table_C_B_D_T_, cbdt_bitmap_format_17
from fontTools.ttLib.tables.C_B_L_C_ import table_C_B_L_C_
from fontTools.ttLib.tables.E_B_L_C_ import (
    Strike, eblc_index_sub_table_1, SbitLineMetrics)
from fontTools.ttLib.tables.BitmapGlyphMetrics import SmallGlyphMetrics
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

UPM = 2048
PPEM = 128
ADV = 2550
IMGDIR = "/root/work/emoji/images"
OUT = "/root/work/emoji/NotoColorEmoji.ttf"
ZWJ, VS16, VS15 = 0x200D, 0xFE0F, 0xFE0E

# 1x1 fully transparent PNG
BLANK_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d4944415478da63fcffff3f030005fe02fea737b7e90000000049454e44ae426082")


def gname(unified):
    return "emoji_u" + "_".join(x.lower() for x in unified.split("-"))


def main():
    data = json.load(open("/root/work/emoji/emoji.json"))
    items = {}
    for e in data:
        if e.get("has_img_apple"):
            items[e["unified"]] = e["image"]
        for sv in (e.get("skin_variations") or {}).values():
            if sv.get("has_img_apple"):
                items[sv["unified"]] = sv["image"]

    seqs, missing = [], 0
    for uni in sorted(items):
        p = os.path.join(IMGDIR, gname(uni) + ".png")
        if os.path.exists(p) and os.path.getsize(p) > 500:
            seqs.append(uni)
        else:
            missing += 1
    print("art:", len(seqs), "missing:", missing, flush=True)

    cp2g = {}
    # 1) plain single-codepoint emoji
    for uni in seqs:
        cps = [int(x, 16) for x in uni.split("-")]
        if len(cps) == 1:
            cp2g[cps[0]] = gname(uni)
    # 2) base + VS16 pairs (so bare base char still renders)
    for uni in seqs:
        cps = [int(x, 16) for x in uni.split("-")]
        if len(cps) == 2 and cps[1] == VS16 and cps[0] not in cp2g:
            cp2g[cps[0]] = gname(uni)
    # 3) joiners must be in cmap or GSUB can never match them
    cp2g[ZWJ] = "uni200D"
    cp2g[VS16] = "uniFE0F"
    cp2g[VS15] = "uniFE0E"

    # placeholder glyphs for codepoints that only appear inside sequences
    need = set()
    for uni in seqs:
        for cp in (int(x, 16) for x in uni.split("-")):
            if cp not in (ZWJ, VS16, VS15):
                need.add(cp)
    placeholders = sorted(cp for cp in need if cp not in cp2g)
    for cp in placeholders:
        nm = "uni%04X" % cp
        cp2g[cp] = nm
    print("placeholder cps:", len(placeholders), flush=True)

    glyph_names = [".notdef"] + [gname(u) for u in seqs] + \
        ["uni%04X" % cp for cp in placeholders] + ["uni200D", "uniFE0F", "uniFE0E"]

    ligs, seen = [], set()
    for uni in seqs:
        cps = [int(x, 16) for x in uni.split("-")]
        if len(cps) < 2:
            continue
        for strip_vs in (False, True):
            comps, ok = [], True
            for cp in cps:
                if cp == VS16:
                    if not strip_vs:
                        comps.append("uniFE0F")
                    continue
                if cp == VS15:
                    if not strip_vs:
                        comps.append("uniFE0E")
                    continue
                if cp == ZWJ:
                    comps.append("uni200D")
                    continue
                g = cp2g.get(cp)
                if g is None:
                    ok = False
                    break
                comps.append(g)
            if ok and len(comps) >= 2:
                key = (tuple(comps), gname(uni))
                if key not in seen:
                    seen.add(key)
                    ligs.append(key)

    print("glyphs", len(glyph_names), "ligatures", len(ligs), flush=True)

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(glyph_names)
    fb.setupCharacterMap(cp2g)
    pen = TTGlyphPen(None)
    empty = pen.glyph()
    fb.setupGlyf({n: empty for n in glyph_names})

    zw = ("uni200D", "uniFE0F", "uniFE0E")
    metrics = {n: (0 if n in zw else ADV, 0) for n in glyph_names}
    metrics[".notdef"] = (ADV, 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=1900, descent=-500)
    fb.setupNameTable({
        "familyName": "Apple Color Emoji",
        "styleName": "Regular",
        "uniqueFontIdentifier": "AppleColorEmoji;13.0",
        "fullName": "Apple Color Emoji",
        "psName": "AppleColorEmoji",
        "version": "Version 13.0",
    })
    fb.setupOS2(sTypoAscender=1900, sTypoDescender=-500, sTypoLineGap=0,
                usWinAscent=1900, usWinDescent=500, usWeightClass=400, fsType=0)
    fb.setupPost()
    fb.setupMaxp()
    font = fb.font

    # ---------- CBDT / CBLC ----------
    cbdt = table_C_B_D_T_()
    cblc = table_C_B_L_C_()
    strike = Strike()
    sub = eblc_index_sub_table_1(None, None)
    strike_data, names = {}, []

    def add_bitmap(nm, png_bytes, w, h):
        g = cbdt_bitmap_format_17(None, None)
        g.metrics = SmallGlyphMetrics()
        g.metrics.height = h
        g.metrics.width = w
        g.metrics.BearingX = 0
        g.metrics.BearingY = min(h - 16, 127)
        g.metrics.Advance = 255
        g.imageData = png_bytes
        strike_data[nm] = g
        names.append(nm)

    for uni in seqs:
        n = gname(uni)
        p = os.path.join(IMGDIR, n + ".png")
        im = Image.open(p).convert("RGBA").resize((PPEM, PPEM), Image.LANCZOS)
        q = im.quantize(colors=256, method=Image.FASTOCTREE,
                        dither=Image.Dither.NONE)
        buf = io.BytesIO()
        q.save(buf, "PNG", optimize=True)
        add_bitmap(n, buf.getvalue(), PPEM, PPEM)

    for cp in placeholders:
        add_bitmap("uni%04X" % cp, BLANK_PNG, 1, 1)

    print("bitmaps", len(names), flush=True)

    gids = sorted(font.getGlyphID(n) for n in names)
    sub.indexFormat = 1
    sub.imageFormat = 17
    sub.names = names
    strike.indexSubTables = [sub]
    bst = strike.bitmapSizeTable
    bst.colorRef = 0
    bst.startGlyphIndex = gids[0]
    bst.endGlyphIndex = gids[-1]
    bst.ppemX = bst.ppemY = PPEM
    bst.bitDepth = 32
    bst.flags = 1

    def lm(asc, desc):
        m = SbitLineMetrics()
        m.ascender = asc
        m.descender = desc
        m.widthMax = PPEM
        m.caretSlopeNumerator = 0
        m.caretSlopeDenominator = 0
        m.caretOffset = 0
        m.minOriginSB = 0
        m.minAdvanceSB = 0
        m.maxBeforeBL = 0
        m.minAfterBL = 0
        m.pad1 = 0
        m.pad2 = 0
        return m

    bst.hori = lm(120, -20)
    bst.vert = lm(120, -20)
    cbdt.version = 3.0
    cblc.version = 3.0
    cblc.strikes = [strike]
    cbdt.strikeData = [strike_data]
    font["CBDT"] = cbdt
    font["CBLC"] = cblc

    # ---------- GSUB ----------
    if ligs:
        lines = ["languagesystem DFLT dflt;", "feature liga {"]
        for comps, gn in ligs:
            lines.append("  sub %s by %s;" % (" ".join(comps), gn))
        lines.append("} liga;")
        fea = "\n".join(lines)
        open("/root/work/emoji/emoji.fea", "w").write(fea)
        addOpenTypeFeaturesFromString(font, fea)
        print("GSUB built", flush=True)

    font.save(OUT)
    print("saved", OUT, round(os.path.getsize(OUT) / 1048576, 1), "MB", flush=True)


if __name__ == "__main__":
    main()
