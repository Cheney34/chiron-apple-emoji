#!/usr/bin/env python3
"""Download Apple 160px emoji art (emoji-data v16.0.0) concurrently."""
import json, os, sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = "https://cdn.jsdelivr.net/gh/iamcal/emoji-data@v16.0.0/img-apple-160/"
DST = "/root/work/emoji/img16"
JS = "/root/work/emoji/emoji16.json"


def gname(u):
    return "emoji_u" + "_".join(x.lower() for x in u.split("-"))


def items():
    d = json.load(open(JS))
    out = {}
    for e in d:
        if e.get("has_img_apple"):
            out[e["unified"]] = 1
        for sv in (e.get("skin_variations") or {}).values():
            if sv.get("has_img_apple"):
                out[sv["unified"]] = 1
    return sorted(out)


def grab(uni):
    dst = os.path.join(DST, gname(uni) + ".png")
    if os.path.exists(dst) and os.path.getsize(dst) > 200:
        return "skip"
    url = BASE + uni.lower().replace("-", "_") + ".png"
    for _ in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=25) as r:
                data = r.read()
            if len(data) > 200:
                with open(dst, "wb") as f:
                    f.write(data)
                return "ok"
        except Exception:
            pass
    return "fail:" + uni


def main():
    os.makedirs(DST, exist_ok=True)
    todo = items()
    print("targets", len(todo), flush=True)
    ok = skip = fail = 0
    fails = []
    with ThreadPoolExecutor(max_workers=64) as ex:
        futs = {ex.submit(grab, u): u for u in todo}
        for i, f in enumerate(as_completed(futs)):
            r = f.result()
            if r == "ok":
                ok += 1
            elif r == "skip":
                skip += 1
            else:
                fail += 1
                fails.append(r)
            if (i + 1) % 500 == 0:
                print("  %d/%d ok=%d skip=%d fail=%d" % (i + 1, len(todo), ok, skip, fail), flush=True)
    print("done ok=%d skip=%d fail=%d" % (ok, skip, fail), flush=True)
    if fails:
        print("failed:", fails[:10], flush=True)
        open("/root/work/emoji/failed16.txt", "w").write("\n".join(fails))


if __name__ == "__main__":
    main()
