#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修正 Chiron 的垂直度量，解决「状态栏电池数字下沉」。

问题现象
--------
状态栏电量百分比、图标内数字、按钮文字这类「固定高度容器里垂直居中」的地方，
数字会比中文明显偏下 1~2 px。正文里看不出来，只有小框最明显。

原因
----
Android 的 TextView 单行居中，基线落在 -(ascent + descent) / 2。

Chiron 的 hhea.ascent 是 1.138 em，比 MiSans 的 1.044 em 大了 0.094 em，
行框中心被顶高，数字就整体显得靠下。叠加数字自身中心偏低，合计约 0.06 em。

关键是 Android 计算 FontMetrics 时：

    top    = min(hhea.ascent,  -usWinAscent)
    bottom = max(hhea.descent,  usWinDescent)

只改 hhea 不改 usWin，top 会被 usWin 锁死，等于没改——这是很容易踩的坑。

做法
----
把 hhea / OS2.typo / OS2.win 三套度量一起对齐到同一个行框中心，
**保持行高总和 1.426 em 不变**，所以中文行距、多行排版、列表高度都不受影响。

用法
----
    python3 fix_metrics.py 输入.ttf 输出.ttf
    python3 fix_metrics.py 输入.ttf 输出.ttf --report   # 只打印度量，不改文件
"""
import argparse
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen

# 目标：行高总和不变（1.426 em），行框中心下移到 365（原 425）
NEW_ASC, NEW_DESC = 1078, -348          # 1000 单位制
NEW_TYPO = (976, -246, 200)
NEW_WIN = (1078, 348)


def dump(tag, f):
    h, hh, os2 = f["head"], f["hhea"], f["OS/2"]
    upem = h.unitsPerEm
    print(f"=== {tag} ===")
    print(f"  upem {upem}  glyphs {f['maxp'].numGlyphs}"
          f"  {'VF' if 'fvar' in f else 'static'}")
    print(f"  hhea  asc {hh.ascent:6d}  desc {hh.descent:6d}  gap {hh.lineGap:4d}")
    print(f"  typo  asc {os2.sTypoAscender:6d}  desc {os2.sTypoDescender:6d}"
          f"  gap {os2.sTypoLineGap:4d}")
    print(f"  win   asc {os2.usWinAscent:6d}  desc {os2.usWinDescent:6d}")

    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    gn = cmap.get(ord("0"))
    if not gn:
        return
    pen = BoundsPen(gs)
    gs[gn].draw(pen)
    if not pen.bounds:
        return
    b = pen.bounds

    # 按状态栏电量胶囊的实测尺寸模拟一次单行居中（32px 字 / 39px 高）
    size, box = 32.0, 39.0
    k = size / upem
    asc, desc = hh.ascent * k, hh.descent * k
    top = -max(asc, os2.usWinAscent * k)
    bot = max(desc, os2.usWinDescent * k)
    baseline = (box - (bot - top)) / 2 - top
    gap_top = baseline - b[3] * k
    gap_bot = box - (baseline - b[1] * k)
    print(f"  数字 bbox {b}  adv {f['hmtx'][gn][0]}")
    print(f"  32px 字 / 39px 框：顶留白 {gap_top:5.1f}px  底留白 {gap_bot:5.1f}px"
          f"  偏差 {(gap_top - gap_bot) / 2:+.1f}px")
    print()


def fix(src, dst):
    f = TTFont(src)
    upem = f["head"].unitsPerEm
    if upem != 1000:
        sys.exit(f"这份脚本按 1000 单位制写的，当前 upem={upem}，需要先换算")

    hh, os2 = f["hhea"], f["OS/2"]
    old_line = hh.ascent - hh.descent + hh.lineGap
    new_line = NEW_ASC - NEW_DESC + 0
    if old_line != new_line:
        print(f"⚠ 行高总和变化 {old_line} → {new_line}，行距会变")

    hh.ascent, hh.descent, hh.lineGap = NEW_ASC, NEW_DESC, 0
    os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = NEW_TYPO
    os2.usWinAscent, os2.usWinDescent = NEW_WIN
    f.save(dst)
    print(f"已写出 {dst}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--report", action="store_true", help="只打印度量，不写出")
    a = ap.parse_args()

    dump("修正前", TTFont(a.src, lazy=True))
    if a.report:
        return
    if not a.dst:
        sys.exit("需要输出路径，或者加 --report 只看不改")
    fix(a.src, a.dst)
    dump("修正后", TTFont(a.dst, lazy=True))


if __name__ == "__main__":
    main()
