#!/usr/bin/env python3
"""Rebuild Apple Color Emoji as an Android CBDT/CBLC font.

Key points vs. the vendor font this replaces:
  * real GSUB (ccmp) ligature table — the vendor file only had Apple's morx,
    which Android/HarfBuzz ignores, so every ZWJ sequence fell apart;
  * multi-strike bitmaps 32/45/60/82/128 px — the vendor file topped out at
    82 px, which gets upscaled into mush on 1.5K/2K screens;
  * 160 px source art from emoji-data v16.0.0 (Unicode 16, iOS 18.4).
"""
import json, os, io, sys
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
ADV = 2400
STRIKES = [32, 45, 60, 82, 128]
IMGDIR = os.environ.get("IMGDIR", "/root/work/emoji/img16")
JSONF = os.environ.get("JSONF", "/root/work/emoji/emoji16.json")
OUT = os.environ.get("OUT", "/root/work/emoji/NotoColorEmoji_new.ttf")
ZWJ, VS16, VS15 = 0x200D, 0xFE0F, 0xFE0E

BLANK_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d4944415478da63fcffff3f030005fe02fea737b7e90000000049454e44ae426082")


def gname(unified):
    return "emoji_u" + "_".join(x.lower() for x in unified.split("-"))


def collect():
    data = json.load(open(JSONF))
    items = {}
    for e in data:
        if e.get("has_img_apple"):
            items[e["unified"]] = 1
        for sv in (e.get("skin_variations") or {}).values():
            if sv.get("has_img_apple"):
                items[sv["unified"]] = 1
    seqs, missing = [], []
    for uni in sorted(items):
        p = os.path.join(IMGDIR, gname(uni) + ".png")
        if os.path.exists(p) and os.path.getsize(p) > 200:
            seqs.append(uni)
        else:
            missing.append(uni)
    print("art:", len(seqs), "missing:", len(missing), flush=True)
    if missing:
        print("  first missing:", missing[:8], flush=True)
    return seqs


def main():
    seqs = collect()

    # ---------- cmap ----------
    cp2g = {}
    for uni in seqs:
        cps = [int(x, 16) for x in uni.split("-")]
        if len(cps) == 1:
            cp2g[cps[0]] = gname(uni)
    for uni in seqs:
        cps = [int(x, 16) for x in uni.split("-")]
        if len(cps) == 2 and cps[1] == VS16 and cps[0] not in cp2g:
            cp2g[cps[0]] = gname(uni)
    cp2g[ZWJ] = "uni200D"
    cp2g[VS16] = "uniFE0F"
    cp2g[VS15] = "uniFE0E"

    # glyphs that only exist inside sequences still need a cmap entry,
    # otherwise GSUB can never see them
    need = set()
    for uni in seqs:
        for cp in (int(x, 16) for x in uni.split("-")):
            if cp not in (ZWJ, VS16, VS15):
                need.add(cp)
    placeholders = sorted(cp for cp in need if cp not in cp2g)
    for cp in placeholders:
        cp2g[cp] = "uni%04X" % cp
    print("placeholder cps:", len(placeholders), flush=True)

    glyph_names = [".notdef"] + [gname(u) for u in seqs] + \
        ["uni%04X" % cp for cp in placeholders] + ["uni200D", "uniFE0F", "uniFE0E"]

    # ---------- ligatures ----------
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

    # ---------- base font ----------
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
        "familyName": "Noto Color Emoji",
        "styleName": "Regular",
        "uniqueFontIdentifier": "NotoColorEmoji;Apple16.0;2026",
        "fullName": "Noto Color Emoji",
        "psName": "NotoColorEmoji",
        "version": "Version 16.0",
    })
    fb.setupOS2(sTypoAscender=1900, sTypoDescender=-500, sTypoLineGap=0,
                usWinAscent=1900, usWinDescent=500, usWeightClass=400, fsType=0)
    fb.setupPost()
    fb.setupMaxp()
    font = fb.font

    # ---------- bitmaps ----------
    cbdt = table_C_B_D_T_()
    cblc = table_C_B_L_C_()
    strikes, all_data = [], []
    blank_metrics = SmallGlyphMetrics()
    blank_metrics.height = 1
    blank_metrics.width = 1
    blank_metrics.BearingX = 0
    blank_metrics.BearingY = 0
    blank_metrics.Advance = 255

    for ppem in STRIKES:
        strike = Strike()
        sub = eblc_index_sub_table_1(None, None)
        sd, names = {}, []

        def add(nm, png, w, h):
            g = cbdt_bitmap_format_17(None, None)
            g.metrics = SmallGlyphMetrics()
            g.metrics.height = h
            g.metrics.width = w
            g.metrics.BearingX = 0
            g.metrics.BearingY = 0 if h == 1 else min(int(h * 5 // 6), 127)
            g.metrics.Advance = min(w, 255)
            g.imageData = png
            sd[nm] = g
            names.append(nm)

        # 位图像素 = advance（2400/2048 em），正好铺满字宽并略作超采样，
        # 与 Apple/Noto 官方的做法一致；ppem 只决定 strike 被选中的尺寸档。
        px = int(round(ppem * ADV / UPM))
        for uni in seqs:
            n = gname(uni)
            p = os.path.join(IMGDIR, n + ".png")
            im = Image.open(p).convert("RGBA").resize((px, px), Image.LANCZOS)
            q = im.quantize(colors=256, method=Image.FASTOCTREE,
                            dither=Image.Dither.NONE)
            buf = io.BytesIO()
            q.save(buf, "PNG", optimize=True)
            add(n, buf.getvalue(), px, px)

        for cp in placeholders:
            add("uni%04X" % cp, BLANK_PNG, 1, 1)

        gids = sorted(font.getGlyphID(n) for n in names)
        sub.indexFormat = 1
        sub.imageFormat = 17
        sub.names = names
        strike.indexSubTables = [sub]
        bst = strike.bitmapSizeTable
        bst.colorRef = 0
        bst.startGlyphIndex = gids[0]
        bst.endGlyphIndex = gids[-1]
        bst.ppemX = bst.ppemY = ppem
        bst.bitDepth = 32
        bst.flags = 1

        def lm(a, d):
            m = SbitLineMetrics()
            m.ascender = a
            m.descender = d
            m.widthMax = min(int(ppem * ADV / UPM), 255)
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

        bst.hori = lm(min(ppem, 127), max(-int(ppem * 0.32), -128))
        bst.vert = lm(min(ppem, 127), max(-int(ppem * 0.32), -128))

        strikes.append(strike)
        all_data.append(sd)
        print("  strike %d px done, %d bitmaps" % (ppem, len(names)), flush=True)

    cbdt.version = 3.0
    cblc.version = 3.0
    cblc.strikes = strikes
    cbdt.strikeData = all_data
    font["CBDT"] = cbdt
    font["CBLC"] = cblc

    # ---------- GSUB ----------
    if ligs:
        lines = ["languagesystem DFLT dflt;", "feature ccmp {"]
        for comps, gn in ligs:
            lines.append("  sub %s by %s;" % (" ".join(comps), gn))
        lines.append("} ccmp;")
        fea = "\n".join(lines)
        open("/root/work/emoji/emoji16.fea", "w").write(fea)
        addOpenTypeFeaturesFromString(font, fea)
        print("GSUB built", flush=True)

    font.save(OUT)
    print("saved", OUT, round(os.path.getsize(OUT) / 1048576, 1), "MB", flush=True)


if __name__ == "__main__":
    main()
