#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v5.0：把 Chiron GoRound TC VF 的西文字母 / 数字 / 半角标点 换成 Merriweather

要点
  1. Merriweather 原件 2000 upm，按 cap height（H）等比缩放对齐 Chiron 的 712
  2. 数字沿用 Chiron 的 600 等宽槽位（保持时钟 / 表格 / 百分比不跳动）
  3. 字重：150 -> Merriweather Light(300)，330 -> Regular(400)，700 -> ExtraBold(800)
     三份实例点数完全一致，直接逐点求差写进 gvar（150 万无一失地保持可变）
  4. CJK 语义的标点（em dash / 省略号 / 间隔号 / 全角标点）保留 Chiron 原样
"""
import os, string, time, zipfile
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.ttProgram import Program
from fontTools.ttLib.tables.TupleVariation import TupleVariation
from fontTools.ttLib.tables._g_l_y_f import GlyphCoordinates, Glyph
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from PIL import Image, ImageDraw, ImageFont

VF = "fonts/Roboto-Regular.ttf"
MW = {300: "merri/t300.ttf", 400: "merri/t400.ttf", 800: "merri/t800.ttf"}
STAGE = "build/mtz7"
OUT = "/workspace/Chiron-Merriweather_v5.0_20261029.mtz"

W_THIN, W_BASE, W_BOLD = 300, 400, 800
DIGIT_ADV = 600          # 保持 Chiron 数字的等宽槽位

# 保留 Chiron 原字形的码位：CJK 语境的破折号 / 省略号 / 间隔号 / 全角标点
KEEP = {0x20, 0x00A0, 0x00AD, 0x00B7, 0x2014, 0x2015, 0x2026}

XML = """<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<theme>
<version><![CDATA[1.00]]></version>
<uiVersion>10</uiVersion>
<author><![CDATA[WorkBuddy]]></author>
<designer><![CDATA[WorkBuddy]]></designer>
<title><![CDATA[Chiron Merriweather]]></title>
<description><![CDATA[Chiron GoRound TC 中文字形，西文字母、数字与半角标点取自 Merriweather，150-700 无极字重]]></description>
<fontWeight>150,200,250,300,350,400,450,500,550,600,650,700</fontWeight>
<authors>
<author locale="zh_CN"><![CDATA[WorkBuddy]]></author>
</authors>
<designers>
<designer locale="zh_CN"><![CDATA[WorkBuddy]]></designer>
</designers>
<titles>
<title locale="zh_CN"><![CDATA[Chiron Merriweather]]></title>
</titles>
<descriptions>
<description locale="zh_CN"><![CDATA[Chiron GoRound TC 中文字形，西文字母、数字与半角标点取自 Merriweather，150-700 无极字重]]></description>
</descriptions>
</theme>
"""


def targets(cmap, mcm):
    out = []
    blocks = [(0x21, 0x7E), (0xC0, 0x24F), (0x1E00, 0x1EFF), (0x2000, 0x206F), (0x20A0, 0x20BF)]
    for a, b in blocks:
        for cp in range(a, b + 1):
            if cp in KEEP:
                continue
            if cp in cmap and cp in mcm:
                out.append(cp)
    return out


def coords_of(font, name):
    g = font["glyf"][name]
    return g.getCoordinates(font["glyf"])


def main():
    c = TTFont(VF)
    mfs = {w: TTFont(p) for w, p in MW.items()}
    cmap, glyf, hmtx, gvar = c.getBestCmap(), c["glyf"], c["hmtx"], c["gvar"]
    mcm = mfs[W_BASE].getBestCmap()

    gs = c.getGlyphSet()

    def bb(n):
        p = BoundsPen(gs)
        gs[n].draw(p)
        return p.bounds

    cap_c = bb(cmap[ord("H")])[3]                      # 基线 -> cap 顶（不含 overshoot）
    mb = BoundsPen(mfs[W_BASE].getGlyphSet())
    mfs[W_BASE].getGlyphSet()[mcm[ord("H")]].draw(mb)
    cap_m = mb.bounds[3]
    sc = cap_c / cap_m
    print(f"cap {cap_m} -> {cap_c}   scale={sc:.5f}")

    def xform(coords, dx=0.0):
        return [(x * sc + dx, y * sc) for x, y in coords]

    done, skip, tight = [], [], []
    for cp in targets(cmap, mcm):
        dn, mn = cmap[cp], mcm[cp]
        try:
            cb, ends, flg = coords_of(mfs[W_BASE], mn)
            tb, e2, _ = coords_of(mfs[W_THIN], mn)
            ob, e3, _ = coords_of(mfs[W_BOLD], mn)
        except Exception:
            skip.append(hex(cp)); continue
        if not len(cb) or len(cb) != len(tb) or len(cb) != len(ob) or list(ends) != list(e2) != list(e3):
            skip.append(hex(cp)); continue

        is_digit = 0x30 <= cp <= 0x39
        if is_digit:
            adv = DIGIT_ADV
            xs = [p[0] for p in cb]
            dx = adv / 2 - (min(xs) + max(xs)) / 2 * sc
        else:
            adv = int(round(mfs[W_BASE]["hmtx"][mn][0] * sc))
            dx = 0.0

        base = [(int(round(x)), int(round(y))) for x, y in xform(cb, dx)]
        thin = [(int(round(x)), int(round(y))) for x, y in xform(tb, dx)]
        bold = [(int(round(x)), int(round(y))) for x, y in xform(ob, dx)]

        g = Glyph()
        g.numberOfContours = len(ends)
        g.endPtsOfContours = list(ends)
        g.flags = bytearray(flg)
        g.coordinates = GlyphCoordinates(base)
        g.program = Program()
        glyf[dn] = g
        g.recalcBounds(glyf)
        hmtx[dn] = (adv, g.xMin)

        if g.xMax > adv + 1 or g.xMin < -1:
            tight.append((chr(cp) if cp < 0x2000 else hex(cp), g.xMin, g.xMax, adv))

        n = len(base)
        dt = [(thin[i][0] - base[i][0], thin[i][1] - base[i][1]) for i in range(n)]
        db = [(bold[i][0] - base[i][0], bold[i][1] - base[i][1]) for i in range(n)]
        tv = []
        if any(a or b for a, b in dt):
            tv.append(TupleVariation({"wght": (-1.0, -1.0, 0.0)}, dt + [(0, 0)] * 4))
        if any(a or b for a, b in db):
            tv.append(TupleVariation({"wght": (0.0, 1.0, 1.0)}, db + [(0, 0)] * 4))
        gvar.variations[dn] = tv
        done.append(cp)

    print(f"replaced {len(done)}  skipped {len(skip)} {skip[:12]}")
    if tight:
        print("ink 超出字宽:", tight[:10])

    # fi / fl 等 f 连字仍是旧造型，从 liga 中摘掉
    t = c["GSUB"].table
    for rec in t.FeatureList.FeatureRecord:
        if rec.FeatureTag == "liga":
            for li in rec.Feature.LookupListIndex:
                for st in t.LookupList.Lookup[li].SubTable:
                    lig = getattr(st, "ligatures", None)
                    if lig and "f" in lig:
                        del lig["f"]

    import shutil
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(f"{STAGE}/fonts", exist_ok=True)
    os.makedirs(f"{STAGE}/preview", exist_ok=True)
    p = f"{STAGE}/fonts/Roboto-Regular.ttf"
    c["head"].modified = int(time.time()) + 2082844800
    c.save(p, reorderTables=True)
    print("font ->", round(os.path.getsize(p) / 1048576, 1), "MB")

    # ---------- 预览 ----------
    def F(size, w):
        f = ImageFont.truetype(p, size)
        try:
            f.set_variation_by_axes([w])
        except Exception:
            pass
        return f

    def draw_page(w, tag, big, small_lines):
        im = Image.new("RGB", (1080, 1920), "white")
        d = ImageDraw.Draw(im)
        d.text((72, 96), "永远的 Chiron", font=F(78, w), fill="#111")
        d.text((72, 210), "× Merriweather", font=F(78, w), fill="#111")
        d.text((72, 330), f"字重 {w} · 150–700 无极可变", font=F(30, w), fill="#b3b3b3")
        d.line((72, 392, 1008, 392), fill="#ededed", width=2)
        y = 440
        for txt, size in small_lines:
            d.text((72, y), txt, font=F(size, w), fill="#1a1a1a")
            y += size + 26
        y += 30
        d.text((72, y), big, font=F(150, w), fill="#111")
        y += 200
        d.text((72, y), "0123456789", font=F(104, w), fill="#111")
        y += 170
        d.text((72, y), "1,299.00  ¥88  −15%  No.7", font=F(46, w), fill="#444")

        # 底部字重梯度，直观展示 150→700
        d.line((72, 1180, 1008, 1180), fill="#ededed", width=2)
        ly = 1220
        for w2 in (150, 330, 500, 700):
            d.text((72, ly), "永久 Aa 09", font=F(58, w2), fill="#1a1a1a")
            d.text((880, ly + 18), f"wght {w2}", font=F(24, w2), fill="#b3b3b3")
            ly += 92
        d.text((72, 1600), "Chiron GoRound TC VF  ×  Merriweather", font=F(28, 330), fill="#c2c2c2")
        im.save(f"{STAGE}/preview/{tag}.jpg", quality=93)
        return im

    body = [("小米的使命是，始终坚持做「感动人心、", 40),
            ("价格厚道」的好产品，让全球每个人都能", 40),
            ("享受科技带来的美好生活。", 40)]
    draw_page(330, "preview_fonts_0", "Ag 09", body)
    draw_page(150, "preview_fonts_1", "Ag 09",
              [("The quick brown fox jumps over the lazy dog", 38),
               ("abcdefghijklmnopqrstuvwxyz ABCDEFGH", 38),
               ("“Good design is as little design as possible.”", 38)])
    draw_page(500, "preview_fonts_2", "Ag 09",
              [("Chiron GoRound TC 与 Merriweather 混排", 40),
               ("Wi-Fi 6E · Bluetooth 5.3 · 5G SA/NSA", 40),
               ("2026年10月29日 星期四 13:20", 40)])
    draw_page(700, "preview_fonts_3", "Ag 09",
              [("标题 Heading 一二三四五", 46),
               ("紧急通知：系统将于今晚 23:00 更新", 40),
               ("Please save your work before updating.", 40)])

    # 小图（285x74）
    Image.open(f"{STAGE}/preview/preview_fonts_0.jpg").resize((285, 507), Image.LANCZOS) \
        .crop((0, 100, 285, 174)).save(f"{STAGE}/preview/preview_fonts_small_0.png")

    open(f"{STAGE}/description.xml", "w", encoding="utf-8").write(XML)

    if os.path.exists(OUT):
        os.remove(OUT)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d0 in ("fonts/", "preview/"):
            zi = zipfile.ZipInfo(d0)
            zi.external_attr = 0o40755 << 16
            z.writestr(zi, b"")
        for root, _, files in os.walk(STAGE):
            for fn in files:
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, STAGE))
    print("mtz ->", round(os.path.getsize(OUT) / 1048576, 1), "MB")


if __name__ == "__main__":
    main()
