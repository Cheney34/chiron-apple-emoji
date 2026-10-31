#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v4.0：Chiron VF + 奇异数字的「拉丁区块」（0-9 + A-Z a-z + 拉丁扩展）
   - 移植方式沿用 v3.0 的最简管线（TTGlyphPen + TransformPen，不做布尔合并）
   - gvar：150 端轻微内收、700 端外扩，点数保持 1:1（点序不变）
   - 保持 Chiron 原字的 advance（排版宽度零变化）
   - 删除 fi/fl 连字（旧 f 造型）
"""
import math, os, sys, time, zipfile
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.ttProgram import Program
from fontTools.ttLib.tables.TupleVariation import TupleVariation
from fontTools.ttLib.tables._g_l_y_f import GlyphCoordinates, Glyph
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from PIL import Image, ImageDraw, ImageFont
import string

SRC = "fonts/misans奇异数字.ttf"
VF = "fonts/Roboto-Regular.ttf"
STAGE = "build/mtz6"
OUT = "/workspace/Chiron奇异数字_v4.0_字母数字_20261029.mtz"

R_BASE = float(os.environ.get("R_BASE", "0"))      # 默认实例：0=保留源字形厚度
R_THIN = float(os.environ.get("R_THIN", "-8"))     # 150 端（负=内收）
R_BOLD = float(os.environ.get("R_BOLD", "15"))      # 700 端（正=外扩）
SCALE_OVERRIDE = os.environ.get("SCALE")

XML = """<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<theme>
<version><![CDATA[1.00]]></version>
<uiVersion>10</uiVersion>
<author><![CDATA[WorkBuddy]]></author>
<designer><![CDATA[WorkBuddy]]></designer>
<title><![CDATA[Chiron奇异数字]]></title>
<description><![CDATA[Chiron GoRound TC 中文字形，数字与西文字母取自 misans奇异数字，提供 150-700 无极变换粗细]]></description>
<fontWeight>150,200,250,300,350,400,450,500,550,600,650,700</fontWeight>
<authors>
<author locale="zh_CN"><![CDATA[WorkBuddy]]></author>
</authors>
<designers>
<designer locale="zh_CN"><![CDATA[WorkBuddy]]></designer>
</designers>
<titles>
<title locale="zh_CN"><![CDATA[Chiron奇异数字]]></title>
</titles>
<descriptions>
<description locale="zh_CN"><![CDATA[Chiron GoRound TC 中文字形，数字与西文字母取自 misans奇异数字，提供 150-700 无极变换粗细]]></description>
</descriptions>
</theme>
"""


def dilate(pts, ends, r):
    """逐点沿法线偏移，r>0 外扩 / r<0 内收。转角补偿限制在 1.15 倍内（避免尖刺）。"""
    out = list(pts)
    start = 0
    for end in ends:
        n = end - start + 1
        cont = pts[start:end + 1]
        if n < 3:
            start = end + 1
            continue
        area = sum(cont[i][0] * cont[(i + 1) % n][1] - cont[(i + 1) % n][0] * cont[i][1]
                   for i in range(n))
        sgn = 1.0 if area < 0 else -1.0
        for i in range(n):
            a, b = cont[(i - 1) % n], cont[(i + 1) % n]
            d1 = (cont[i][0] - a[0], cont[i][1] - a[1])
            d2 = (b[0] - cont[i][0], b[1] - cont[i][1])
            l1, l2 = math.hypot(*d1), math.hypot(*d2)
            if l1 < 1e-6 or l2 < 1e-6:
                continue
            n1 = (sgn * -d1[1] / l1, sgn * d1[0] / l1)
            n2 = (sgn * -d2[1] / l2, sgn * d2[0] / l2)
            nx, ny = n1[0] + n2[0], n1[1] + n2[1]
            L = math.hypot(nx, ny)
            if L < 1e-3:
                continue
            nx, ny = nx / L, ny / L
            k = min(1.15, 1.0 / max(0.87, n1[0] * nx + n1[1] * ny))
            out[start + i] = (cont[i][0] + nx * r * k, cont[i][1] + ny * r * k)
        start = end + 1
    return out


def main():
    src = TTFont(SRC)
    dst = TTFont(VF)
    s_gs, s_cmap = src.getGlyphSet(), src.getBestCmap()
    d_gs = dst.getGlyphSet()
    cmap, glyf, hmtx, gvar = dst.getBestCmap(), dst["glyf"], dst["hmtx"], dst["gvar"]

    def bb(gs, g):
        p = BoundsPen(gs); gs[g].draw(p); return p.bounds

    def cap(f, gs, cm, ch):
        b = bb(gs, cm[ord(ch)]); return b[3] - b[1]

    s_cap, d_cap = cap(src, s_gs, s_cmap, "H"), cap(dst, d_gs, cmap, "H")
    s_xh, d_xh = bb(s_gs, s_cmap[ord("x")])[3], bb(d_gs, cmap[ord("x")])[3]
    scale = float(SCALE_OVERRIDE) if SCALE_OVERRIDE else (d_cap / s_cap)
    print(f"cap {s_cap}->{d_cap}  x-height {s_xh}->{d_xh}  scale={scale:.4f}")

    cps = list(range(0x30, 0x3A)) + [ord(c) for c in string.ascii_letters]
    cps += list(range(0xC0, 0x180)) + list(range(0x1E00, 0x1F00))

    done, skip = [], []
    for c in cps:
        if c not in s_cmap or c not in cmap:
            skip.append(hex(c)); continue
        sn, dn = s_cmap[c], cmap[c]
        if dn not in glyf or glyf[dn].isComposite():
            skip.append(hex(c)); continue
        b = bb(s_gs, sn)
        if not b:
            skip.append(hex(c)); continue
        s_adv = src["hmtx"][sn][0]
        adv = hmtx[dn][0]                      # 保留 Chiron 字宽
        # 局部缩放：保证字形外扩后仍在字宽内（重音字母等窄槽位）
        avail = adv - 2 * abs(R_BOLD) - 2
        sc = scale
        w = b[2] - b[0]
        if w * sc > avail and w > 0:
            sc = max(0.62, avail / w)
        cx = (b[0] + b[2]) / 2
        dx = adv / 2 - cx * sc                 # 视觉居中到字宽（与 v3.0 数字定位一致）

        pen = TTGlyphPen(None)
        s_gs[sn].draw(TransformPen(pen, (sc, 0, 0, sc, dx, 0)))
        g0 = pen.glyph()
        if not g0.numberOfContours:
            skip.append(hex(c)); continue
        g0.program = Program()

        raw = list(g0.coordinates)
        base = dilate(raw, g0.endPtsOfContours, R_BASE) if R_BASE else raw
        thin = dilate(raw, g0.endPtsOfContours, R_THIN)
        bold = dilate(raw, g0.endPtsOfContours, R_BOLD)

        if R_BASE:
            gb0 = Glyph()
            gb0.numberOfContours = g0.numberOfContours
            gb0.endPtsOfContours = list(g0.endPtsOfContours)
            gb0.flags = bytearray(g0.flags)
            gb0.coordinates = GlyphCoordinates([(int(round(x)), int(round(y))) for x, y in base])
            gb0.program = Program()
            g0 = gb0
        glyf[dn] = g0
        glyf[dn].recalcBounds(glyf)
        hmtx[dn] = (adv, glyf[dn].xMin)

        n = len(base)
        dt = [(int(round(thin[i][0] - base[i][0])), int(round(thin[i][1] - base[i][1]))) for i in range(n)]
        db = [(int(round(bold[i][0] - base[i][0])), int(round(bold[i][1] - base[i][1]))) for i in range(n)]
        tv = []
        if any(abs(a) + abs(b2) > 0 for a, b2 in dt):
            tv.append(TupleVariation({"wght": (-1.0, -1.0, 0.0)}, dt + [(0, 0)] * 4))
        if any(abs(a) + abs(b2) > 0 for a, b2 in db):
            tv.append(TupleVariation({"wght": (0.0, 1.0, 1.0)}, db + [(0, 0)] * 4))
        gvar.variations[dn] = tv
        done.append(c)

    print("replaced", len(done), "skipped", len(skip))

    # 删除 fi / fl 连字（旧 f 造型会与新 f 冲突）
    t = dst["GSUB"].table
    for rec in t.FeatureList.FeatureRecord:
        if rec.FeatureTag == "liga":
            for li in rec.Feature.LookupListIndex:
                for st in t.LookupList.Lookup[li].SubTable:
                    lig = getattr(st, "ligatures", None)
                    if lig and "f" in lig:
                        del lig["f"]

    os.makedirs(f"{STAGE}/fonts", exist_ok=True)
    os.makedirs(f"{STAGE}/preview", exist_ok=True)
    p = f"{STAGE}/fonts/Roboto-Regular.ttf"
    dst["head"].modified = int(time.time()) + 2082844800
    dst.save(p, reorderTables=True)
    print("font ->", round(os.path.getsize(p) / 1048576, 1), "MB")

    im = Image.new("RGB", (1080, 1920), "white")
    d = ImageDraw.Draw(im)
    d.text((70, 130), "奇异数字", font=ImageFont.truetype(p, 74), fill="#111")
    d.text((70, 235), "Chiron GoRound TC · 150–700 无极字重", font=ImageFont.truetype(p, 32), fill="#999")
    d.text((70, 390), "0123456789", font=ImageFont.truetype(p, 112), fill="#111")
    d.text((70, 530), "ABCDEFGHIJKLM", font=ImageFont.truetype(p, 68), fill="#111")
    d.text((70, 625), "abcdefghijklm", font=ImageFont.truetype(p, 68), fill="#111")
    y = 760
    for t2, s2 in (("10:28", 92), ("2026.10.28", 92), ("¥1,299.00", 88)):
        d.text((70, y), t2, font=ImageFont.truetype(p, s2), fill="#111"); y += 135
    d.text((70, 1200), "小米的使命是，始终坚持做", font=ImageFont.truetype(p, 44), fill="#333")
    d.text((70, 1265), "「感动人心、价格厚道」的好产品，", font=ImageFont.truetype(p, 44), fill="#333")
    d.text((70, 1330), "让全球每个人都能享受科技", font=ImageFont.truetype(p, 44), fill="#333")
    d.text((70, 1395), "带来的美好生活。", font=ImageFont.truetype(p, 44), fill="#333")
    d.text((70, 1530), "MiSans · HyperOS · Wi-Fi 5G", font=ImageFont.truetype(p, 40), fill="#666")
    d.text((70, 1600), "电量 78% · 步数 12480", font=ImageFont.truetype(p, 40), fill="#666")
    d.text((70, 1670), "No.7 · 42% · 3.5kg", font=ImageFont.truetype(p, 40), fill="#666")
    im.save(f"{STAGE}/preview/preview_fonts_0.jpg", quality=92)
    im.resize((285, 507), Image.LANCZOS).crop((0, 120, 285, 194)).save(
        f"{STAGE}/preview/preview_fonts_small_0.png")

    open(f"{STAGE}/description.xml", "w", encoding="utf-8").write(XML)

    if os.path.exists(OUT):
        os.remove(OUT)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d0 in ("fonts/", "preview/"):
            zi = zipfile.ZipInfo(d0); zi.external_attr = 0o40755 << 16; z.writestr(zi, b"")
        for root, _, files in os.walk(STAGE):
            for fn in files:
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, STAGE))
    print("mtz ->", round(os.path.getsize(OUT) / 1048576, 1), "MB")


if __name__ == "__main__":
    main()
