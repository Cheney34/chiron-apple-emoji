#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修正合并字体里三个 Merriweather 移植字符的观感问题。

  @ U+0040  中心 0.243 em，与 Chiron 中文字框中心（0.370）差 0.127 em，
            中文界面里「@昵称」明显下沉。
            -> 等比缩到 0.920 em 高（Roboto 原版就是这个高度），
               中心抬到 0.350 em，与中文基本齐平。

  * U+002A  Merriweather 的星号是六条放射状短杠（类似「米」字）。
            -> 三根矩形杆做布尔并集，自绘「直角六角星」。

  # U+0023  Merriweather 的井号在拨号盘里比数字小一圈。
            -> 整字放大到 0.842 em 高，笔画同步变粗。

为什么星号要做得比系统原星号小（这是刻意的，别改回去）
  拨号盘给同一行的三个键配了三种字号，实测同一张截图（1220×1358）：

      0  48×68 px   -> 字号约 93 px/em（基准）
      #  42×56 px   -> 字号约 76 px/em（0.82 倍）
      *  66×72 px   -> 字号约 197 px/em（2.1 倍）

  星号被放大 2.1 倍，所以字体里只要做到 0.325 em 高、杆宽 32，
  到拨号盘正好是 64×59 px、笔画 6 px，与数字、井号同一视觉重量；
  若按系统原星号 0.366 em 做，拨号盘里就是 72 px 高、笔画 16 px，
  看起来像一朵开过头的花。代价是正文字号下 * 偏小偏细，这是取舍。

历史版本（都验证过，供回溯）
  v6.5    * 376×400、中心 470     拨号盘偏大偏下（比原星号高 11%、低 58 单位）
  v6.3_refix(1) * 388×366、中心 531  尺寸对，但没算拨号盘的 2.1 倍放大
  v6.3_refix(2) * 325×297、杆宽 32   按拨号盘视觉反向补偿，当前版本

字形全部重建轮廓，gvar 记录一并删除，可变字重下保持同一形状。
输入可以是任意版本的合并字体（重复执行结果不变，@ 与 # 幂等）。

用法：
    pip install shapely
    python3 fix_glyphs.py <输入字体> <输出字体>
"""
import argparse
import math

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates
from fontTools.ttLib.tables.ttProgram import Program
from shapely.geometry import Polygon
from shapely.ops import unary_union

# ---------- @ ----------
AT_HEIGHT = 920      # @ 目标高度（1/1000 em），Roboto 原版 0.920
AT_CENTER = 350      # @ 目标中心（1/1000 em），Chiron 中文 370，留 20 余量

# ---------- * ----------
STAR_ARM = 335       # 杆长，直接决定星号高度
STAR_BAR = 34        # 杆宽，拨号盘 2.1 倍放大后约 6.7 px
STAR_STRETCH = 1.0   # 横向拉伸，直角星天然比圆头星窄
STAR_CENTER = 530.5  # 中心（1/1000 em），Roboto 528.5 / Chiron 530.5

# ---------- # ----------
HASH_HEIGHT = 800    # # 目标高度（1/1000 em），拨号盘 0.82 倍字号下约 61 px


def transform(g, sx, sy, dx, dy):
    g.coordinates = GlyphCoordinates(
        [(int(round(x * sx + dx)), int(round(y * sy + dy))) for x, y in g.coordinates])
    return len(g.coordinates)


def transform_gvar(f, gname, n, sx, sy):
    for tv in f["gvar"].variations.get(gname) or []:
        c = list(tv.coordinates)
        tv.coordinates = ([(int(round(x * sx)), int(round(y * sy)))
                            for x, y in c[:n]] + c[n:])


def star_outline(cx, cy, arm, bar, stretch):
    """三根矩形杆（90° / 30° / 150°）求并集，取外轮廓。

    并集后是一条闭合 18 点多边形，全直线段——这就是直角六角星。
    """
    def bar_poly(deg):
        a = math.radians(deg)
        ux, uy = math.cos(a), math.sin(a)
        vx, vy = -math.sin(a), math.cos(a)
        hl, hw = arm / 2, bar / 2
        return Polygon([(su * hl * ux + sv * hw * vx, su * hl * uy + sv * hw * vy)
                        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))])

    u = unary_union([bar_poly(90), bar_poly(30), bar_poly(150)])
    poly = u if u.geom_type == "Polygon" else max(u.geoms, key=lambda p: p.area)
    return [(int(round(x * stretch + cx)), int(round(y + cy)))
            for x, y in list(poly.exterior.coords)[:-1]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    a = ap.parse_args()

    f = TTFont(a.src)
    cmap = f.getBestCmap()
    glyf, hmtx = f["glyf"], f["hmtx"]

    # ---------- @ ----------
    dn = cmap[0x40]
    g = glyf[dn]
    y0, y1 = g.yMin, g.yMax
    s = AT_HEIGHT / (y1 - y0)
    dy = AT_CENTER - (y0 + y1) / 2 * s
    adv_new = int(round(hmtx[dn][0] * s))
    dx = adv_new / 2 - (g.xMin + g.xMax) / 2 * s
    n = transform(g, s, s, dx, dy)
    transform_gvar(f, dn, n, s, s)
    g.recalcBounds(glyf)
    hmtx[dn] = (adv_new, g.xMin)
    print(f"@  {n} 点  {g.xMax - g.xMin}×{g.yMax - g.yMin}  "
          f"中心 {(g.yMax + g.yMin) / 2:.0f}  adv {adv_new}")

    # ---------- # ----------
    dn = cmap[0x23]
    g = glyf[dn]
    y0, y1 = g.yMin, g.yMax
    s = HASH_HEIGHT / (y1 - y0)
    cx = (g.xMin + g.xMax) / 2
    dx = cx - cx * s
    dy = y0 - y0 * s           # 底边钉在基线
    n = transform(g, s, s, dx, dy)
    transform_gvar(f, dn, n, s, s)
    g.recalcBounds(glyf)
    hmtx[dn] = (hmtx[dn][0], g.xMin)
    print(f"#  {n} 点  {g.xMax - g.xMin}×{g.yMax - g.yMin}  "
          f"bbox=({g.xMin},{g.yMin},{g.xMax},{g.yMax})  adv {hmtx[dn][0]}")

    # ---------- * ----------
    dn = cmap[0x2A]
    pts = star_outline(hmtx[dn][0] / 2, STAR_CENTER,
                       STAR_ARM, STAR_BAR, STAR_STRETCH)
    g = Glyph()
    g.numberOfContours = 1
    g.endPtsOfContours = [len(pts) - 1]
    g.flags = bytearray([1] * len(pts))
    g.coordinates = GlyphCoordinates(pts)
    g.program = Program()
    glyf[dn] = g
    g.recalcBounds(glyf)
    hmtx[dn] = (hmtx[dn][0], g.xMin)
    # 自绘轮廓没有 gvar 数据，留着会让非默认字重按旧点序施加位移，必须删
    if dn in f["gvar"].variations:
        del f["gvar"].variations[dn]
    print(f"*  {len(pts)} 点  {g.xMax - g.xMin}×{g.yMax - g.yMin}  "
          f"bbox=({g.xMin},{g.yMin},{g.xMax},{g.yMax})  "
          f"中心 {(g.yMax + g.yMin) / 2:.0f}  adv {hmtx[dn][0]}")

    f.save(a.out, reorderTables=True)
    f.close()
    print("->", a.out)


if __name__ == "__main__":
    main()
