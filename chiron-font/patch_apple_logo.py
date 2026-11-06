#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Apple 私用区 U+F8FF 的苹果 logo 写进 Chiron VF。

U+F8FF 是苹果系统里唯一的私用区码位（U+E000–U+F8FF 里苹果只用了这一个），
iOS / macOS 上打出来是苹果标志。Chiron GoRound TC 在这个码位放的是一颗带字母 N
的五角星，换字体后从备忘录、Keynote 复制过来的标志会变成星号，所以 6.4 起换掉。

用法
    python3 patch_apple_logo.py \
        --src  PingFangSC-Regular.ttf \
        --font Roboto-Regular.ttf \
        --out  Roboto-v6.4.ttf

设计约束（改这个文件前先读这段）
  1. 源与目标的 upem 必须都是 1000。苹果 logo 在苹方里是按 1000 upem 画的，
     若目标字体是 2048，得先 scale_upem，否则字号会对不上。
  2. gvar 里该字形的 delta 必须删掉。Chiron 这个码位的 gvar 条目本来就没有 tuple，
     删掉是幂等操作；但只要留着一个空条目以外的数据，字形就会被拖变形。
  3. 不要动 hmtx 以外的度量。字宽取苹果原版的 1000（占满全角），
     lsb 用重算后的 xMin，行高与基线保持不变。
"""
import argparse
import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

CP = 0xF8FF


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="带苹果 logo 的源字体（PingFangSC-Regular.ttf）")
    ap.add_argument("--font", required=True, help="要改的 Chiron 字体（VT 或静态 TTF）")
    ap.add_argument("--out", required=True)
    ap.add_argument("--upem", type=int, default=1000, help="源与目标共用的 upem，默认 1000")
    a = ap.parse_args()

    src, dst = TTFont(a.src), TTFont(a.font)
    sc, dc = src.getBestCmap(), dst.getBestCmap()
    if CP not in sc:
        sys.exit("源字体没有 U+F8FF，确认是不是苹方原版")
    if CP not in dc:
        sys.exit("目标字体没有 U+F8FF 的 cmap 映射，本脚本只替换、不新增码位")

    sname, dname = sc[CP], dc[CP]
    if src["head"].unitsPerEm != a.upem or dst["head"].unitsPerEm != a.upem:
        sys.exit("upem 不匹配：src=%d dst=%d 期望=%d"
                 % (src["head"].unitsPerEm, dst["head"].unitsPerEm, a.upem))

    # 复合字形会被 draw 展开成简单轮廓，避免带上目标字体没有的组件引用
    pen = TTGlyphPen(None)
    src.getGlyphSet()[sname].draw(pen)
    glyph = pen.glyph()
    glyph.recalcBounds(dst["glyf"])

    dst["glyf"][dname] = glyph
    adv = src["hmtx"][sname][0]
    dst["hmtx"][dname] = (adv, glyph.xMin)

    # 字形要是带 delta，字重一变就会歪；苹果这个标志本身也是单字重
    if "gvar" in dst and dname in dst["gvar"].variations:
        n = len(dst["gvar"].variations[dname])
        del dst["gvar"].variations[dname]
        print("gvar: 删除 %s 的 %d 条 delta" % (dname, n))

    print("%s: adv %d, bounds x %d–%d, y %d–%d"
          % (dname, adv, glyph.xMin, glyph.xMax, glyph.yMin, glyph.yMax))
    dst.save(a.out)
    print("saved:", a.out)


if __name__ == "__main__":
    main()
