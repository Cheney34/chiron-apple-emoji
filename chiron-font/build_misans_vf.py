#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成「MiSans 身份 + 可变字重」版本：
  - 以 ChironGoRoundTC-奇异数字-VF 为源，子集化到常用字集
  - 内部 name 改为 MiSans 家族（让系统按 MiSans 处理字重/排版开关）
  - 输出 fonts/Roboto-Regular.ttf（主题引擎已验证可加载的文件名）
"""
import codecs, os, time, zipfile
import shutil
from fontTools.ttLib import TTFont
from fontTools import subset

VF = "/workspace/ChironGoRoundTC-奇异数字-VF.ttf"
STAGE = "build/mtz2"
OUT = "/workspace/ChironQiyi-MiSansVF.mtz"


def charset():
    cps = set(range(0x20, 0x7F))
    cps |= set(range(0xA0, 0x180))        # Latin-1 / Extended-A
    cps |= set(range(0x2000, 0x2070))     # 通用标点
    cps |= set(range(0x20A0, 0x20C0))     # 货币
    cps |= set(range(0x2100, 0x2140))     # 字母式符号
    cps |= set(range(0x2150, 0x2190))     # 数字形式
    cps |= set(range(0x2190, 0x2200))     # 箭头
    cps |= set(range(0x2460, 0x2500))     # 带圈数字
    cps |= set(range(0x2500, 0x2580))     # 制表符
    cps |= set(range(0x25A0, 0x2600))     # 几何图形
    cps |= set(range(0x3000, 0x3040))     # CJK 标点
    cps |= set(range(0xFF00, 0xFFF0))     # 全角
    for enc in ("gb2312", "big5"):
        for hi in range(0xA1, 0xFF):
            for lo in range(0xA1, 0xFF):
                try:
                    ch = bytes([hi, lo]).decode(enc)
                except Exception:
                    continue
                if len(ch) == 1:
                    cps.add(ord(ch))
    return cps


def main():
    cps = charset()
    print("目标字符集:", len(cps))

    font = TTFont(VF)
    cmap = font.getBestCmap()
    keep = sorted(c for c in cps if c in cmap)
    print("字体实际覆盖:", len(keep))

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["DSIG"]
    opts.retain_gids = False

    sub = subset.Subsetter(options=opts)
    sub.populate(unicodes=keep)
    sub.subset(font)

    # 伪装成 MiSans 家族
    for rec in font["name"].names:
        if rec.nameID == 1:
            rec.string = "MiSans"
        elif rec.nameID == 4:
            rec.string = "MiSans Regular"
        elif rec.nameID == 6:
            rec.string = "MiSans-Regular"
        elif rec.nameID == 3:
            rec.string = "4.010;HANYI;MiSans-Regular"
        elif rec.nameID == 5:
            rec.string = "Version 4.010;MiSans"
    font["OS/2"].usWeightClass = 400
    font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~0b100001) | 0b1000000
    font["head"].fontRevision = 4.010
    font["head"].modified = int(time.time()) + 2082844800

    os.makedirs(f"{STAGE}/fonts", exist_ok=True)
    p = f"{STAGE}/fonts/Roboto-Regular.ttf"
    font.save(p, reorderTables=True)
    print("VF(子集) ->", p, round(os.path.getsize(p) / 1048576, 1), "MB",
          "glyphs", font["maxp"].numGlyphs,
          "fvar", "wght" in [a.axisTag for a in font["fvar"].axes] if "fvar" in font else False)

    # 预览图沿用
    os.makedirs(f"{STAGE}/preview", exist_ok=True)
    for fn in os.listdir("build/mtz/preview"):
        shutil.copy(f"build/mtz/preview/{fn}", f"{STAGE}/preview/{fn}")
    shutil.copy("build/mtz/description.xml", f"{STAGE}/description.xml")

    if os.path.exists(OUT):
        os.remove(OUT)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, _, files in os.walk(STAGE):
            for fn in files:
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, STAGE))
    print("mtz ->", OUT, round(os.path.getsize(OUT) / 1048576, 1), "MB")


if __name__ == "__main__":
    main()
