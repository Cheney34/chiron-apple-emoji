#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只替换成品包里的 emoji 字体，其余文件逐字节保留。

为什么需要它：
  改 emoji 库（比如 16.0 → 17.0）时，正文 `Roboto-Regular.ttf`、预览图、安装脚本
  都不该有任何变化。重跑 `build_v6.py` 会连带重新生成正文与预览图，三个渠道的字体
  sha256 就可能对不上（6.3 出过这个事故）。这里改成「原地换一个条目」。

两个坑它替你堵住：
  · KSU / Magisk 包里 `customize.sh` 等脚本是 755，用 zipfile 重写会掉成 644 → 装不上
  · MTZ 里正文字体被重新压缩后字节变了，虽然内容一样，但 md5 对不上就没法证明「没动」

用法：
  python3 tools/repack_emoji.py --base 旧包 --emoji 新字体.ttf --kind mtz|ksu \\
      --version 6.5 --out 新包

  --kind 决定替换哪个路径、改哪些版本字段：
    mtz → fonts/NotoColorEmoji.ttf        + description.xml 的 <version>
    ksu → system/fonts/NotoColorEmoji.ttf + module.prop 的 version / versionCode
"""
import argparse
import os
import re
import sys
import zipfile

PATH = {
    "mtz": "fonts/NotoColorEmoji.ttf",
    "ksu": "system/fonts/NotoColorEmoji.ttf",
}


def patch_mtz(data, ver):
    s = data.decode("utf-8")
    # 两种 description.xml 都见过：<version>6.5</version> / <version><![CDATA[6.5]]></version>
    s = re.sub(r"<version>\s*(?:<!\[CDATA\[)?[0-9.]+\]?\]?>\s*</version>",
               "<version>%s</version>" % ver, s, count=1)
    s = re.sub(r"<version><!\[CDATA\[[0-9.]+\]\]></version>",
               "<version><![CDATA[%s]]></version>" % ver, s, count=1)
    return s.encode("utf-8")


def patch_prop(data, ver):
    s = data.decode("utf-8")
    s = re.sub(r"^version=.*$", "version=v%s" % ver, s, count=1, flags=re.M)
    m = re.search(r"^versionCode=(\d+)$", s, re.M)
    if m:
        s = s.replace(m.group(0), "versionCode=%d" % (int(m.group(1)) + 1), 1)
    return s.encode("utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="上一版成品（.mtz 或模块 .zip）")
    ap.add_argument("--emoji", required=True, help="新的 NotoColorEmoji.ttf")
    ap.add_argument("--kind", required=True, choices=["mtz", "ksu"])
    ap.add_argument("--version", required=True, help="新版本号，如 6.5")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    inner = PATH[a.kind]
    emoji = open(a.emoji, "rb").read()

    with zipfile.ZipFile(a.base) as zin:
        if inner not in zin.namelist():
            sys.exit("%s 里没有 %s，--kind 选错了？" % (a.base, inner))
        os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
        with zipfile.ZipFile(a.out, "w") as zout:
            for info in zin.infolist():
                data = emoji if info.filename == inner else zin.read(info.filename)
                if a.kind == "mtz" and info.filename == "description.xml":
                    data = patch_mtz(data, a.version)
                elif a.kind == "ksu" and info.filename == "module.prop":
                    data = patch_prop(data, a.version)

                ni = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                ni.compress_type = info.compress_type
                ni.external_attr = info.external_attr      # 关键：保住 755
                ni.internal_attr = info.internal_attr
                ni.create_system = info.create_system
                ni.comment = info.comment
                ni.extra = info.extra
                zout.writestr(ni, data)

    print("写入 %s  %.1f MB" % (a.out, os.path.getsize(a.out) / 1048576))


if __name__ == "__main__":
    main()
