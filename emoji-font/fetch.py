import json, os, sys, urllib.request, concurrent.futures as cf

BASE = "https://cdn.jsdelivr.net/gh/iamcal/emoji-data@v15.1.2/img-apple-160/"
OUT = "/root/work/emoji/images"
os.makedirs(OUT, exist_ok=True)

d = json.load(open("/root/work/emoji/emoji.json"))
seqs = []
for e in d:
    if e.get("has_img_apple"):
        seqs.append((e["unified"], e["image"]))
    for sv in (e.get("skin_variations") or {}).values():
        if sv.get("has_img_apple"):
            seqs.append((sv["unified"], sv["image"]))
seqs = sorted(set(seqs))
print("total", len(seqs), flush=True)


def name(unified):
    return "emoji_u" + "_".join(x.lower() for x in unified.split("-")) + ".png"


def fetch(item):
    unified, img = item
    dst = os.path.join(OUT, name(unified))
    if os.path.exists(dst) and os.path.getsize(dst) > 500:
        return "skip"
    url = BASE + img
    for _ in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
            if len(data) > 500 and data[:8] == b"\x89PNG\r\n\x1a\n":
                open(dst, "wb").write(data)
                return "ok"
        except Exception:
            pass
    return "fail:" + img


ok = skip = 0
fails = []
with cf.ThreadPoolExecutor(max_workers=96) as ex:
    for i, r in enumerate(ex.map(fetch, seqs)):
        if r == "ok":
            ok += 1
        elif r == "skip":
            skip += 1
        else:
            fails.append(r)
        if i % 250 == 0:
            print(f"{i}/{len(seqs)} ok={ok} skip={skip} fail={len(fails)}", flush=True)
print("DONE ok", ok, "skip", skip, "fail", len(fails), flush=True)
print("fails", fails[:20], flush=True)
