#!/usr/bin/env python3
"""Package the MTZ theme: Chiron GoRound TC VF + Merriweather + Apple Color Emoji.

用法
    python3 build_v6.py \
        --src-font /path/to/Roboto-Regular.ttf \
        --emoji    /path/to/NotoColorEmoji.ttf \
        --out      Chiron-Emoji-v6.2-MTZ.mtz

设计约束（改这个文件前先读这段）
  1. description.xml 的根节点保持 <MIUI-Theme>。审计报告指出参照包用的是
     <theme>，但 v6.2 用 <MIUI-Theme> 在真机上已经装得上、跑得动，
     在拿到一台能反复刷机的测试机之前不动它 —— 换根节点失败是「装不上」，
     代价远大于收益。仍要补的是四个 locale 块和版本同步。
  2. emoji 字体必须过 verify_emoji()：真彩、至少两档、advance 归一 2400。
     v6.2 的包之所以「发糊、偏小」，是塞进了一份 256 色单档、advance 2550
     的历史字体。校验不过就拒绝打包，而不是打出一个能装但难看的东西。
  3. 垂直度量校验：Chiron 原厂 hhea.ascent 1138 会让状态栏电量数字下沉 3px，
     修正后是 1078。低于 1078 说明源字体是没修过的版本，拒绝打包。
"""
import argparse
import io
import os
import shutil
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont

DEFAULT_VERSION = "6.2"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

# 期望值：与 emoji-font/build17.py 的 UPM / ADV 保持一致
EXPECT_UPM = 2048
EXPECT_ADV = 2400
MIN_STRIKES = 2          # MTZ 版压体积，允许双档；单档不算（v6.2 的错）
MIN_CMAP = 1440          # Root 版 1445，MTZ 版 1433 说明字符表不全
EXPECT_HHEA_ASCENT = 1078
EXPECT_HHEA_DESCENT = -348


# ── 校验 ────────────────────────────────────────────────────────────────────

def png_color_type(data):
    """从 PNG 头读 IHDR 的 color type。6 = RGBA 真彩，3 = 调色板。"""
    if not data.startswith(PNG_MAGIC) or len(data) < 26:
        return None
    return data[25]


def verify_emoji(path):
    """返回 (problems, info)。problems 非空即拒绝打包。"""
    from fontTools.ttLib import TTFont

    problems, info = [], {}
    if not os.path.exists(path):
        return ["emoji 字体不存在: %s" % path], info

    font = TTFont(path, lazy=True)
    info["size"] = os.path.getsize(path)

    if "CBDT" not in font or "CBLC" not in font:
        return ["缺 CBDT/CBLC，不是彩色位图字体（Android 会画成空白）"], info

    cbdt = font["CBDT"]
    strikes = [s.bitmapSizeTable for s in cbdt.strikeData]
    info["strikes"] = len(strikes)
    if len(strikes) < MIN_STRIKES:
        problems.append(
            "只有 %d 档位图（要求 ≥%d）。单档会在系统缩放时发虚；"
            "用 STRIKES=45,96 重跑 emoji-font/build17.py" % (len(strikes), MIN_STRIKES))

    # 位图真彩 + 实际像素尺寸。glyph 0 不一定有位图，取该档里第一个真实条目
    first = next(iter(strikes[0].values())) if strikes and strikes[0] else None
    if first is not None:
        ctype = png_color_type(first.imageData)
        info["png_color_type"] = ctype
        if ctype != 6:
            problems.append(
                "位图不是 RGBA 真彩（PNG color type=%s，6 才是真彩）。"
                "256 色调色板会让脸部渐变出现色阶" % ctype)
        try:
            im = Image.open(io.BytesIO(first.imageData))
            info["px"] = im.size[0]
        except Exception:
            problems.append("首档位图无法用 PIL 解码，Android 也大概率解不开")

    upm = font["head"].unitsPerEm
    adv = font["hmtx"].metrics.get("emoji_u1f600") or font["hmtx"].metrics.get(
        list(font["hmtx"].metrics)[0])
    info["upm"], info["adv"] = upm, adv
    if upm != EXPECT_UPM or adv != EXPECT_ADV:
        problems.append(
            "advance width 未归一：upem=%d adv=%d，期望 %d/%d。"
            "图形会缩在格子里（v6.2 只占 80%%）" % (upm, adv, EXPECT_UPM, EXPECT_ADV))

    info["cmap"] = len(font.getBestCmap())
    if info["cmap"] < MIN_CMAP:
        problems.append(
            "cmap 只有 %d 个码位（要求 ≥%d），说明字符表缺项，"
            "会回退成安卓黑白符号" % (info["cmap"], MIN_CMAP))

    feats = set()
    if "GSUB" in font and font["GSUB"].table.FeatureList:
        feats = {fr.FeatureTag for fr in font["GSUB"].table.FeatureList.FeatureRecord}
    info["gsub"] = sorted(feats)
    if "ccmp" not in feats:
        problems.append(
            "GSUB 缺 ccmp 特性（当前 %s）。组合/肤色/旗帜靠 ccmp 连字，"
            "缺了会被拆成单个字符" % (sorted(feats) or "空"))

    font.close()
    return problems, info


def verify_text_font(path):
    from fontTools.ttLib import TTFont

    problems, info = [], {}
    if not os.path.exists(path):
        return ["正文字体不存在: %s" % path], info
    font = TTFont(path, lazy=True)
    hhea = font["hhea"]
    info["ascent"], info["descent"] = hhea.ascent, hhea.descent
    info["size"] = os.path.getsize(path)
    if "fvar" in font:
        axes = [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                for a in font["fvar"].axes]
        info["axes"] = axes
    if hhea.ascent != EXPECT_HHEA_ASCENT or hhea.descent != EXPECT_HHEA_DESCENT:
        if hhea.ascent > EXPECT_HHEA_ASCENT:
            why = "偏高，是 Chiron 原厂度量，行框中心被抬高、电量数字下沉约 3px"
        else:
            why = "不是 fix_metrics.py 的修正值"
        problems.append(
            "hhea.ascent/descent = %d/%d，期望 %d/%d —— %s"
            % (hhea.ascent, hhea.descent,
               EXPECT_HHEA_ASCENT, EXPECT_HHEA_DESCENT, why))
    font.close()
    return problems, info


# ── description.xml ─────────────────────────────────────────────────────────

def build_xml(version, title, author, desc_zh, desc_en):
    """根节点 <MIUI-Theme> 保持不变（真机已验证），补四个 locale 块并同步版本。"""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<MIUI-Theme>
  <title>{title}</title>
  <titles>
    <zh_CN>{title}</zh_CN>
    <en_US>{title}</en_US>
  </titles>
  <author>{author}</author>
  <authors>
    <zh_CN>{author}</zh_CN>
    <en_US>{author}</en_US>
  </authors>
  <designer>{author}</designer>
  <designers>
    <zh_CN>{author}</zh_CN>
    <en_US>{author}</en_US>
  </designers>
  <version>{version}</version>
  <uiVersion>10</uiVersion>
  <fontWeight>150,200,250,300,350,400,450,500,550,600,650,700</fontWeight>
  <description>{desc_zh}</description>
  <descriptions>
    <zh_CN>{desc_zh}</zh_CN>
    <en_US>{desc_en}</en_US>
  </descriptions>
</MIUI-Theme>
"""


# ── 预览图 ──────────────────────────────────────────────────────────────────

def make_previews(stage, src_font, emoji_font):
    ef = ImageFont.truetype(emoji_font, 128)

    def _f(size, w):
        f = ImageFont.truetype(src_font, size)
        try:
            f.set_variation_by_axes([w])
        except Exception:
            pass
        return f

    def draw_emoji(canvas, x, y_center, size, ch):
        tmp = Image.new("RGBA", (260, 260), (0, 0, 0, 0))
        ImageDraw.Draw(tmp).text((40, 40), ch, font=ef, embedded_color=True)
        bbox = tmp.getbbox()
        if not bbox:
            return
        tmp = tmp.crop(bbox).resize((size, size), Image.LANCZOS)
        canvas.paste(tmp, (int(x), int(y_center - size / 2)), tmp)

    def draw_mixed(canvas, d, x, y, size, w, parts, fill="#111", gap=0):
        f = _f(size, w)
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
            draw_mixed(im, d, 72, y, 54, w2, [("t", "永久 Ag 09 "), ("e", "😀")])
            d.text((880, y + 18), f"wght {w2}", font=_f(24, 330), fill="#b3b3b3")
            y += 88

        gy = 1170
        grid = ["😀", "😂", "🥰", "😎", "🤔", "😭", "😡", "🥳", "😴",
                "👍", "👎", "👏", "🙏", "💪", "👀", "🧠", "👶", "🧑‍💻",
                "🍎", "🍔", "🍺", "⚽", "🚗", "✈️", "🏠", "💡", "🎁",
                "❤️", "💔", "✨", "🔥", "💯", "⚠️", "✅", "❌", "❓"]
        for r in range(4):
            for c in range(9):
                draw_emoji(im, 72 + c * 104, gy + r * 98 + 44, 82, grid[r * 9 + c])

        d.text((72, 1700),
               "Chiron GoRound TC VF  ×  Merriweather  ×  Apple Color Emoji",
               font=_f(26, 330), fill="#c2c2c2")
        im.save(os.path.join(stage, "preview", f"{tag}.jpg"), quality=93)

    ROW = ["😀", "😂", "🥰", "😎", "🤔", "😭", "👍🏽", "🎉", "❤️"]
    page(330, "preview_fonts_0", "字重 330 · 默认",
         [[("t", "小米的使命是，始终坚持做「感动人心、")],
          [("t", "价格厚道」的好产品 "), ("e", "😀")],
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
          [("t", "2026年11月1日 星期日 13:20 "), ("e", "⏰")]],
         ROW)

    page(700, "preview_fonts_3", "字重 700 · 最粗",
         [[("t", "紧急通知：系统将于今晚 23:00 更新 "), ("e", "⚠️")],
          [("t", "Please save your work before updating.")],
          [("t", "标题 Heading 一二三四五 "), ("e", "📢")]],
         ROW)

    Image.open(os.path.join(stage, "preview", "preview_fonts_0.jpg")) \
        .resize((285, 507), Image.LANCZOS).crop((0, 100, 285, 174)) \
        .save(os.path.join(stage, "preview", "preview_fonts_small_0.png"))


# ── 打包 ────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src-font", default=os.environ.get(
        "SRC_FONT", "build/mtz7/fonts/Roboto-Regular.ttf"))
    ap.add_argument("--emoji", default=os.environ.get(
        "EMOJI", "build/emoji/NotoColorEmoji.ttf"))
    ap.add_argument("--stage", default=os.environ.get("STAGE", "build/mtz"))
    ap.add_argument("--out", default=os.environ.get("OUT"))
    ap.add_argument("--version", default=os.environ.get("VERSION", DEFAULT_VERSION))
    ap.add_argument("--force", action="store_true",
                    help="跳过规格校验（仅用于本地试验，不要用于发行）")
    a = ap.parse_args()

    out = a.out or f"Chiron-Emoji-v{a.version}-MTZ.mtz"

    print("== 校验正文字体 ==")
    tp, ti = verify_text_font(a.src_font)
    print("   ", ti)
    print("== 校验 emoji 字体 ==")
    ep, ei = verify_emoji(a.emoji)
    print("   ", ei)

    problems = tp + ep
    if problems:
        print("\n!! 规格不合格，拒绝打包：", file=sys.stderr)
        for p in problems:
            print("   -", p, file=sys.stderr)
        if not a.force:
            sys.exit(1)
        print("   --force 已指定，继续。", file=sys.stderr)

    if os.path.isdir(a.stage):
        shutil.rmtree(a.stage)
    os.makedirs(os.path.join(a.stage, "fonts"))
    os.makedirs(os.path.join(a.stage, "preview"))

    shutil.copy(a.src_font, os.path.join(a.stage, "fonts", "Roboto-Regular.ttf"))
    shutil.copy(a.emoji, os.path.join(a.stage, "fonts", "NotoColorEmoji.ttf"))
    print("text font %.1f MB / emoji font %.1f MB" % (
        os.path.getsize(a.src_font) / 1048576, os.path.getsize(a.emoji) / 1048576))

    make_previews(a.stage, a.src_font, a.emoji)

    xml = build_xml(
        a.version,
        "Chiron Emoji",
        "Chiron × Merriweather × Apple Emoji",
        "Chiron GoRound TC VF · 西文 Merriweather · Apple 彩色 emoji",
        "Chiron GoRound TC VF · Merriweather Latin · Apple Color Emoji",
    )
    with open(os.path.join(a.stage, "description.xml"), "w", encoding="utf-8") as f:
        f.write(xml)

    if os.path.exists(out):
        os.remove(out)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d0 in ("fonts/", "preview/"):
            zi = zipfile.ZipInfo(d0)
            zi.external_attr = 0o40755 << 16
            z.writestr(zi, b"")
        for root, _, files in os.walk(a.stage):
            for fn in files:
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, a.stage))

    mb = os.path.getsize(out) / 1048576
    print("mtz -> %s  %.1f MB  version=%s" % (out, mb, a.version))
    if mb > 120:
        print("提示：超过 120 MB。主题引擎对单个 mtz 的体积耐受度未验证，"
              "建议用 --strikes 45,96 出更小的 emoji 字体。", file=sys.stderr)


if __name__ == "__main__":
    main()
