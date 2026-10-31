#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把「misans奇异数字」的 ASCII 数字移植到 Chiron GoRound TC VF，并保留可变字体。

要点：
  1. 轮廓缩放至 Chiron 数字高度（714/1000 em），字宽沿用 600，基线对齐；
  2. 用“逐点法线偏移”做字重校准，使默认实例（wght=330）的笔画厚度与 Chiron 一致；
  3. 偏移后按原高度归一化，保证加粗/变细只改笔画、不改字面高；
  4. 点数与点序保持不变 → 直接重写 gvar 的 delta，可变性完整保留。
"""
import math
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.TupleVariation import TupleVariation
from fontTools.ttLib.tables._g_l_y_f import GlyphCoordinates, Glyph
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen

SRC_DIGIT = "fonts/misans奇异数字.ttf"
TARGET = "fonts/Roboto-Regular.ttf"     # Chiron GoRound TC VF，默认 wght=330
OUT = "out/ChironGoRoundTC-奇异数字-VF.ttf"

CAP_TARGET = 714
ADV_TARGET = 600

# 以 Chiron '0' 竖壁厚度校准（150 / 330 / 700 → 45 / 107 / 174，upem=1000）
R_BASE = 0.0      # 默认实例：内收至与 Chiron 笔画一致（竖壁 ≈107）
R_THIN = 0.0      # wght=150：与默认一致（再内收会使细节笔画断裂）
R_BOLD = 16.0     # wght=700：外扩（外扩不会自交，安全）


def offset_points(pts, ends, flags, r, sgn=1.0):
    """逐点沿轮廓法线偏移（r>0 外扩=加粗）。点数、点序不变。

    切线取“相邻点”（含控制点）差分，曲线上的法线才垂直于局部走向；
    尖锐拐角用两条边法线的角平分线，并按 1/cos 补偿转角处的偏移距离。
    绕向由 sgn 全局控制（TrueType 外轮廓顺时针时取 1）。
    """
    out = list(pts)
    start = 0
    for end in ends:
        n = end - start + 1
        cont = pts[start:end + 1]
        if n < 3:
            start = end + 1
            continue
        for i in range(n):
            p_prev, p_next = cont[(i - 1) % n], cont[(i + 1) % n]
            d1 = (cont[i][0] - p_prev[0], cont[i][1] - p_prev[1])
            d2 = (p_next[0] - cont[i][0], p_next[1] - cont[i][1])
            l1 = math.hypot(*d1); l2 = math.hypot(*d2)
            if l1 < 1e-6 or l2 < 1e-6:
                continue
            n1 = (sgn * -d1[1] / l1, sgn * d1[0] / l1)
            n2 = (sgn * -d2[1] / l2, sgn * d2[0] / l2)
            nx, ny = n1[0] + n2[0], n1[1] + n2[1]
            L = math.hypot(nx, ny)
            if L < 1e-3:
                nx, ny = n1
            else:
                nx, ny = nx / L, ny / L
            cos_half = max(0.87, (n1[0] * nx + n1[1] * ny))   # 限制转角补偿 ≤1.15 倍，避免拉出尖刺
            out[start + i] = (cont[i][0] + nx * r / cos_half, cont[i][1] + ny * r / cos_half)
        start = end + 1
    return out


def _ink_area(pts, ends):
    import pathops
    p = pathops.Path()
    start = 0
    for end in ends:
        cont = pts[start:end + 1]
        p.moveTo(*cont[0])
        for pt in cont[1:]:
            p.lineTo(*pt)
        p.close()
        start = end + 1
    return abs(p.area)


def clean_glyph(glyphset, name, scale, dx):
    """合并重叠轮廓 → 缩放/平移 → 转回 TrueType 二次曲线，返回 Glyph。"""
    import pathops
    from fontTools.pens.cu2quPen import Cu2QuPen

    p = pathops.Path()
    glyphset[name].draw(p.getPen())
    p.simplify(fix_winding=True, keep_starting_points=False)
    pen = TTGlyphPen(None)
    p.draw(pen)
    g = pen.glyph()
    g.coordinates = GlyphCoordinates([(int(round(x * scale + dx)), int(round(y * scale)))
                                      for x, y in g.coordinates])
    return g


def variant(g0, r, h0):
    """偏移 → 按设计高度归一化 → 水平居中到字宽。"""
    base_pts = list(g0.coordinates)
    ends = g0.endPtsOfContours
    pts = offset_points(base_pts, ends, g0.flags, r, 1.0)
    if r:
        a0, a1 = _ink_area(base_pts, ends), _ink_area(pts, ends)
        if (a1 < a0) == (r > 0):          # 加粗却变小 → 法线方向反了，全局翻转
            pts = offset_points(base_pts, ends, g0.flags, r, -1.0)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    y0min = min(p[1] for p in g0.coordinates)
    s = (h0 - y0min) / (max(ys) - min(ys)) if max(ys) > min(ys) else 1.0
    pts = [(x * s, y * s) for x, y in pts]
    dy = y0min - min(ys) * s
    pts = [(x, y + dy) for x, y in pts]
    cx = (min(xs) + max(xs)) / 2 * s
    shift = ADV_TARGET / 2 - cx
    return [(x + shift, y) for x, y in pts]


def make_glyph(g0, pts):
    g = Glyph()
    g.numberOfContours = g0.numberOfContours
    g.endPtsOfContours = list(g0.endPtsOfContours)
    g.flags = bytearray(g0.flags)
    g.coordinates = GlyphCoordinates([(int(round(x)), int(round(y))) for x, y in pts])
    from fontTools.ttLib.tables.ttProgram import Program
    g.program = Program()
    return g


def main():
    src = TTFont(SRC_DIGIT)
    dst = TTFont(TARGET)
    s_gs, s_cmap, cmap = src.getGlyphSet(), src.getBestCmap(), dst.getBestCmap()
    glyf, hmtx, gvar = dst["glyf"], dst["hmtx"], dst["gvar"]

    tops = []
    for c in range(0x30, 0x3A):
        bp = BoundsPen(s_gs); s_gs[s_cmap[c]].draw(bp); tops.append(bp.bounds[3])
    scale = CAP_TARGET / max(tops)
    print(f"移植缩放系数 {scale:.5f}")

    rows = []
    for c in range(0x30, 0x3A):
        sname, dname = s_cmap[c], cmap[c]
        bp = BoundsPen(s_gs); s_gs[sname].draw(bp); sb = bp.bounds
        s_adv = src["hmtx"][sname][0]
        sc_center = (sb[0] + sb[2]) / 2 * scale
        want = ADV_TARGET * ((sb[0] + sb[2]) / 2 / s_adv)
        dx = round(want - sc_center)

        g0 = clean_glyph(s_gs, sname, scale, dx)
        h0 = max(p[1] for p in g0.coordinates)

        base = variant(g0, -R_BASE, h0)
        thin = variant(g0, -R_THIN, h0)
        bold = variant(g0, +R_BOLD, h0)

        gb = make_glyph(g0, base)
        glyf[dname] = gb
        glyf[dname].recalcBounds(glyf)
        hmtx[dname] = (ADV_TARGET, glyf[dname].xMin)

        n = len(base)
        zeros = [(0, 0)] * 4
        d150 = [(int(round(thin[i][0] - base[i][0])), int(round(thin[i][1] - base[i][1]))) for i in range(n)]
        d700 = [(int(round(bold[i][0] - base[i][0])), int(round(bold[i][1] - base[i][1]))) for i in range(n)]
        tuples = []
        if any(v != (0, 0) for v in d150):
            tuples.append(TupleVariation({"wght": (-1.0, -1.0, 0.0)}, d150 + zeros))
        if any(v != (0, 0) for v in d700):
            tuples.append(TupleVariation({"wght": (0.0, 1.0, 1.0)}, d700 + zeros))
        gvar.variations[dname] = tuples
        rows.append((chr(c), n, (gb.xMin, gb.yMin, gb.xMax, gb.yMax)))

    import time
    dst["head"].modified = int(time.time()) + 2082844800
    dst.save(OUT, reorderTables=True)
    print("字符 点数 包围盒")
    for r in rows:
        print(r)


if __name__ == "__main__":
    main()
