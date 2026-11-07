#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓 Apple emoji 位图与元数据（Emoji 17.0 / iOS 26 字形）。

为什么不用 npm 的 emoji-datasource-apple：
  那个包停在 16.0.0，17.0 的 7 个新表情（🫪 变形脸 / 🫯 打斗云团 / 🫈 毛怪 /
  🫍 虎鲸 / 🛘 山体滑坡 / 🪊 长号 / 🪎 宝箱）以及 150 条新 ZWJ 序列都还没有。
  上游 iamcal/emoji-data 的 master 已有 17.0 全套 Apple PNG（2026-11 实测
  `1faea.png` 与 Emojipedia 的 `source/apple/453` 逐像素一致）。

做法：
  1. 从 raw.githubusercontent 取 emoji.json（带 short_name / added_in / has_img_apple）；
  2. 流式下载仓库 tarball，只解 `img-apple-160/` 下的 PNG（边下边解，不落 490 MB 临时包）；
  3. 文件名统一成 `emoji_u1f600.png` / `emoji_u1f1e8_1f1e6.png`，与 build17.py 的 IMGDIR 约定一致。

产物：
  emoji-font/img/              3946 张 160×160 RGBA PNG（含肤色变体）
  emoji-font/emoji-data.json   Emoji 17.0 元数据（1919 条）

用法：
  python3 emoji-font/fetch17.py                 # 全量
  python3 emoji-font/fetch17.py --max 40 --out /tmp/try   # 冒烟测试
"""
import argparse
import io
import json
import os
import shutil
import tarfile
import urllib.request

REV = "e77759c296ed37beb0dbd63908b43d8619509c6d"   # iamcal/emoji-data master，2026-11
RAW = "https://raw.githubusercontent.com/iamcal/emoji-data/%s/" % REV
TAR = "https://codeload.github.com/iamcal/emoji-data/tar.gz/%s" % REV
UA = {"User-Agent": "Mozilla/5.0"}
HERE = os.path.dirname(os.path.abspath(__file__))


def grab(url, timeout=180):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout)


def gname(unified):
    return "emoji_u" + "_".join(x.lower() for x in unified.split("-")) + ".png"


def sequences(data):
    """所有带 Apple 位图的 unified 串（含肤色变体），17.0 共 3946 条。"""
    out = {}
    for e in data:
        if e.get("has_img_apple"):
            out[e["unified"]] = 1
        for sv in (e.get("skin_variations") or {}).values():
            if sv.get("has_img_apple"):
                out[sv["unified"]] = 1
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=HERE, help="工作目录（img/ 与 emoji-data.json 落这里）")
    ap.add_argument("--max", type=int, default=0, help="只解前 N 个，用于冒烟")
    a = ap.parse_args()

    img = os.path.join(a.out, "img")
    os.makedirs(img, exist_ok=True)

    print("1/2 emoji.json ...", flush=True)
    with grab(RAW + "emoji.json") as r:
        raw = r.read()
    data = json.loads(raw.decode("utf-8"))
    with open(os.path.join(a.out, "emoji-data.json"), "wb") as f:
        f.write(raw)
    seqs = sequences(data)
    print("    %d 条，其中 added_in=17.0 的基字符 %d 个"
          % (len(seqs), sum(1 for e in data if e.get("added_in") == "17.0" and "-" not in e["unified"])),
          flush=True)

    print("2/2 位图（流式解包 tarball）...", flush=True)
    n = 0
    prefix = "img-apple-160/"
    with grab(TAR, timeout=600) as r:
        tf = tarfile.open(fileobj=r, mode="r|gz")
        for m in tf:
            if not m.isfile() or prefix not in m.name:
                continue
            base = os.path.basename(m.name)
            if not base.endswith(".png"):
                continue
            dst = os.path.join(img, "emoji_u" + base[:-4].lower().replace("-", "_") + ".png")
            f = tf.extractfile(m)
            if f is None:
                continue
            with open(dst, "wb") as out:
                shutil.copyfileobj(f, out)
            n += 1
            if n % 500 == 0:
                print("    %d" % n, flush=True)
            if a.max and n >= a.max:
                print("    --max %d 触发，提前停止" % a.max, flush=True)
                break

    print("完成：%d 张位图 -> %s" % (n, img), flush=True)
    if not a.max:
        miss = [u for u in seqs if not os.path.exists(os.path.join(img, gname(u)))]
        print("缺图 %d 条%s" % (len(miss), ("：" + ", ".join(miss[:5])) if miss else ""), flush=True)


if __name__ == "__main__":
    main()
