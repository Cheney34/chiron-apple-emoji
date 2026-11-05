#!/usr/bin/env python3
"""Package v6.0: Chiron + Merriweather + Apple Color Emoji."""
import os, time, zipfile, shutil
from PIL import Image, ImageDraw, ImageFont

SRC_FONT = "/root/work/build/mtz7/fonts/Roboto-Regular.ttf"
EMOJI = "/root/work/emoji/NotoColorEmoji.ttf"
STAGE = "/root/work/build/mtz8"
OUT = "/workspace/Chiron-Merriweather_v6.0_AppleEmoji_20261029.mtz"

XML = """<?xml version="1.0" encoding="UTF-8"?>
<MIUI-Theme>
  <title>Chiron Merriweather</title>
  <author>Chiron × Merriweather × Apple Emoji</author>
  <designer>Chiron × Merriweather × Apple Emoji</designer>
  <version>6.0</version>
  <uiVersion>10</uiVersion>
  <fontWeight>150,200,250,300,350,400,450,500,550,600,650,700</fontWeight>
  <description>Chiron GoRound TC VF · 西文 Merriweather · 彩色 emoji Apple Color Emoji</description>
</MIUI-Theme>
"""

EMOJI_PX = 128
ef = ImageFont.truetype(EMOJI, EMOJI_PX)


def draw_emoji(canvas, x, y_center, size, ch):
    tmp = Image.new("RGBA", (260, 260), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((40, 40), ch, font=ef, embedded_color=True)
    bbox = tmp.getbbox()
    if not bbox:
        return
    tmp = tmp.crop(bbox).resize((size, size), Image.LANCZOS)
    canvas.paste(tmp, (int(x), int(y_center - size / 2)), tmp)


def draw_mixed(canvas, d, x, y, size, w, parts, fill="#111", gap=0):
    """parts: list of ("t", text) or ("e", emoji string)"""
    f = ImageFont.truetype(SRC_FONT, size)
    try:
        f.set_variation_by_axes([w])
    except Exception:
        pass
    cursor = x
    for kind, val in parts:
        if kind == "t":
            d.text((cursor, y), val, font=f, fill=fill)
            cursor += d.textlength(val, font=f)
        else:
            draw_emoji(canvas, cursor, y + size * 0.55, int(size * 0.98), val)
            cursor += size * 1.06
        cursor += gap
    return cursor


def main():
    import shutil as sh
    if os.path.isdir(STAGE):
        sh.rmtree(STAGE)
    os.makedirs(f"{STAGE}/fonts")
    os.makedirs(f"{STAGE}/preview")

    sh.copy(SRC_FONT, f"{STAGE}/fonts/Roboto-Regular.ttf")
    sh.copy(EMOJI, f"{STAGE}/fonts/NotoColorEmoji.ttf")
    print("text font", round(os.path.getsize(SRC_FONT) / 1048576, 1), "MB")
    print("emoji font", round(os.path.getsize(EMOJI) / 1048576, 1), "MB")

    def page(w, tag, title_sub, lines, emoji_row):
        im = Image.new("RGB", (1080, 1920), "white")
        d = ImageDraw.Draw(im)
        d.text((72, 96), "永远的 Chiron", font=_f(78, w), fill="#111")
        d.text((72, 210), "× Merriweather", font=_f(78, w), fill="#111")
        d.text((72, 330), title_sub, font=_f(30, w), fill="#b3b3b3")
        d.line((72, 392, 1008, 392), fill="#ededed", width=2)

        y = 440
        for parts in lines:
            draw_mixed(im, d, 72, y, 40, w, parts)
            y += 66

        y += 24
        d.text((72, y), "Emoji", font=_f(30, 330), fill="#b3b3b3")
        y += 52
        x = 72
        for ch in emoji_row:
            draw_emoji(im, x, y + 44, 88, ch)
            x += 100
        y += 120

        d.line((72, y, 1008, y), fill="#ededed", width=2)
        y += 40
        for w2 in (150, 330, 700):
            draw_mixed(im, d, 72, y, 54, w2,
                       [("t", "永久 Ag 09 "), ("e", "😀")])
            d.text((880, y + 18), f"wght {w2}", font=_f(24, 330), fill="#b3b3b3")
            y += 88

        # emoji grid fills the lower half
        gy = 1170
        grid = ["😀", "😂", "🥰", "😎", "🤔", "😭", "😡", "🥳", "😴",
                "👍", "👎", "👏", "🙏", "💪", "👀", "🧠", "👶", "🧑‍💻",
                "🍎", "🍔", "🍺", "⚽", "🚗", "✈️", "🏠", "💡", "🎁",
                "❤️", "💔", "✨", "🔥", "💯", "⚠️", "✅", "❌", "❓"]
        for r in range(4):
            for c in range(9):
                ch = grid[r * 9 + c]
                draw_emoji(im, 72 + c * 104, gy + r * 98 + 44, 82, ch)

        d.text((72, 1700), "Chiron GoRound TC VF  ×  Merriweather  ×  Apple Color Emoji",
               font=_f(26, 330), fill="#c2c2c2")
        im.save(f"{STAGE}/preview/{tag}.jpg", quality=93)

    def _f(size, w):
        f = ImageFont.truetype(SRC_FONT, size)
        try:
            f.set_variation_by_axes([w])
        except Exception:
            pass
        return f

    ROW = ["😀", "😂", "🥰", "😎", "🤔", "😭", "👍🏽", "🎉", "❤️"]
    page(330, "preview_fonts_0", "字重 330 · 默认",
         [[("t", "小米的使命是，始终坚持做「感动人心、")],
          [("t", "价格厚道」的好产品 ", ), ("e", "😀")],
          [("t", "让全球每个人都能享受科技带来的美好生活")]],
         ROW)

    page(150, "preview_fonts_1", "字重 150 · 最细",
         [[("t", "The quick brown fox jumps over the lazy dog")],
          [("t", "abcdefghijklmnopqrstuvwxyz 0123456789")],
          [("t", "“Good design is as little design as possible.”")]],
         ROW)

    page(500, "preview_fonts_2", "字重 500 · 中等",
         [[("t", "Chiron 与 Merriweather 混排 "), ("e", "🎉")],
          [("t", "Wi-Fi 6E · Bluetooth 5.3 · 5G SA/NSA")],
          [("t", "2026年10月29日 星期四 13:20 "), ("e", "⏰")]],
         ROW)

    page(700, "preview_fonts_3", "字重 700 · 最粗",
         [[("t", "紧急通知：系统将于今晚 23:00 更新 "), ("e", "⚠️")],
          [("t", "Please save your work before updating.")],
          [("t", "标题 Heading 一二三四五 "), ("e", "📢")]],
         ROW)

    Image.open(f"{STAGE}/preview/preview_fonts_0.jpg").resize((285, 507), Image.LANCZOS) \
        .crop((0, 100, 285, 174)).save(f"{STAGE}/preview/preview_fonts_small_0.png")

    open(f"{STAGE}/description.xml", "w", encoding="utf-8").write(XML)

    if os.path.exists(OUT):
        os.remove(OUT)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d0 in ("fonts/", "preview/"):
            zi = zipfile.ZipInfo(d0)
            zi.external_attr = 0o40755 << 16
            z.writestr(zi, b"")
        for root, _, files in os.walk(STAGE):
            for fn in files:
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, STAGE))
    print("mtz ->", round(os.path.getsize(OUT) / 1048576, 1), "MB")


if __name__ == "__main__":
    main()
