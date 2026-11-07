#!/system/bin/sh
# ============================================================
# Chiron × Apple Emoji  ——  类原生 KSU / Magisk 字体模块
# 模块 id：chiron_apple_emoji（沿用 5.x / 6.2 这条线，不另起新模块）
#
# 安装期做的事：
#   0. 扫一遍 /data/adb/modules，报告还有谁在改同一批字体（只报告，不动别人的模块）
#   1. 探测系统 Roboto 的真实文件名（Roboto-Regular.ttf / Roboto[wdth,wght].ttf …）
#      并把模块里的字体改成同名，靠 magic mount 覆盖，配置一个字都不动
#   2. 读系统真实的 font_fallback.xml，在 zh-Hans / zh-Hant 家族首位
#      插入我们的字体（只加不删），生成模块内的副本
#   3. 任何一步失败都只跳过，不生成坏文件 —— 最差情况是中文没换，绝不会开不了机
# ============================================================

SKIPUNZIP=0

if ! command -v ui_print >/dev/null 2>&1; then
    ui_print() { echo "$1"; }
fi

MODDIR=${0%/*}
SYS_FONTS=/system/fonts

# ---------- 0. 冲突检测 ----------
# 同一路径只能有一个来源：KSU / Magisk 按 /data/adb/modules 的目录名顺序挂载，
# 后挂的覆盖先挂的，不看版本号新旧。这里只报告，不替用户禁用别人的模块。
SELF_ID="chiron_apple_emoji"
CONFLICTS=""
for d in /data/adb/modules/*; do
    [ -d "$d" ] || continue
    [ -f "$d/module.prop" ] || continue
    mid=$(grep -m1 '^id=' "$d/module.prop" 2>/dev/null | cut -d= -f2-)
    [ "$mid" = "$SELF_ID" ] && continue
    HIT=""
    [ -f "$d/system/fonts/NotoColorEmoji.ttf" ] && HIT="NotoColorEmoji.ttf"
    for f in "$d/system/fonts/"Roboto*.ttf; do
        if [ -f "$f" ]; then
            HIT="${HIT:+$HIT + }$(basename "$f")"
            break
        fi
    done
    [ -z "$HIT" ] && continue
    mname=$(grep -m1 '^name=' "$d/module.prop" 2>/dev/null | cut -d= -f2-)
    mver=$(grep -m1 '^version=' "$d/module.prop" 2>/dev/null | cut -d= -f2-)
    ui_print "! 冲突：$mid  ${mver}"
    ui_print "    $mname"
    ui_print "    它也在提供：$HIT"
    CONFLICTS="$CONFLICTS $mid"
done

if [ -n "$CONFLICTS" ]; then
    ui_print "! 同一路径只能有一个来源，后挂载的会覆盖先挂载的（不看版本号）"
    ui_print "! 装完请把上面这些模块关掉或卸载，否则会出现「替换成功但画不出来」"
else
    ui_print "- 没有其它模块抢同一批字体"
fi

# 6.3–6.5 临时用过 chiron_ksu_font，本版回到 chiron_apple_emoji
if [ -d /data/adb/modules/chiron_ksu_font ]; then
    ui_print "- 检测到 6.3–6.5 的临时模块 chiron_ksu_font"
    ui_print "  本版已回到 chiron_apple_emoji 这条线，装完请把它卸载"
fi

ui_print " "
ui_print "======================================"
ui_print " Chiron × Apple Emoji"
ui_print " 类原生字体模块"
ui_print "======================================"
ui_print " "

# ---------- 1. 探测 Roboto 的实际文件名 ----------
TARGET_FONT=""
for n in "Roboto-Regular.ttf" "Roboto[wdth,wght].ttf" "Roboto[wdth,wght].otf" \
         "Roboto-VF.ttf" "RobotoVF.ttf" "Roboto.ttf"; do
    if [ -f "$SYS_FONTS/$n" ]; then
        TARGET_FONT="$n"
        break
    fi
done

if [ -z "$TARGET_FONT" ]; then
    # 兜底：按前缀扫一遍
    for f in "$SYS_FONTS"/Roboto*; do
        [ -f "$f" ] || continue
        case "$f" in
            *Italic*|*Thin*|*Light*|*Medium*|*Bold*|*Black*) continue ;;
        esac
        TARGET_FONT="${f##*/}"
        break
    done
fi

if [ -z "$TARGET_FONT" ]; then
    ui_print "! 没找到系统 Roboto 字体，改用默认名 Roboto-Regular.ttf"
    TARGET_FONT="Roboto-Regular.ttf"
else
    ui_print "- 系统默认字体：$TARGET_FONT"
fi

# 模块里的字体改名成系统实际使用的名字
SRC_FONT="$MODPATH/system/fonts/Roboto-Regular.ttf"
if [ "$TARGET_FONT" != "Roboto-Regular.ttf" ] && [ -f "$SRC_FONT" ]; then
    mv -f "$SRC_FONT" "$MODPATH/system/fonts/$TARGET_FONT"
    ui_print "- 字体已重命名为：$TARGET_FONT"
fi

# ---------- 2. 处理 font_fallback.xml ----------
# Android 15 起 fonts.xml 已废弃，Minikin 真正读的是 font_fallback.xml
FALLBACK=""
for p in /system/etc/font_fallback.xml /system_ext/etc/font_fallback.xml \
         /product/etc/font_fallback.xml; do
    if [ -f "$p" ]; then
        FALLBACK="$p"
        break
    fi
done

if [ -z "$FALLBACK" ]; then
    ui_print "! 未找到 font_fallback.xml（可能是 Android 14 及更早的系统）"
    LEGACY=/system/etc/fonts.xml
    if [ -f "$LEGACY" ]; then
        ui_print "- 回退到 fonts.xml"
        FALLBACK="$LEGACY"
    fi
fi

if [ -n "$FALLBACK" ]; then
    ui_print "- 配置文件：$FALLBACK"
    mkdir -p "$MODPATH/system/etc"
    DEST="$MODPATH/system/etc/$(basename "$FALLBACK")"

    # 构造要插入的 9 个字重（VF 靠 wght 轴实例化）
    INS=""
    for w in 100 200 300 400 500 600 700 800 900; do
        INS="${INS}        <font weight=\"$w\" style=\"normal\" supportedAxes=\"wght\">$TARGET_FONT</font>
"
    done

    # 用 awk 在 zh-Hans / zh-Hant 家族起始标签后插入。
    # 只插入、不删除、不改动原有任何一行。
    awk -v ins="$INS" '
        /<family[^>]*lang="[^"]*zh-Hans/ { print; printf "%s", ins; next }
        /<family[^>]*lang="[^"]*zh-Hant/ { print; printf "%s", ins; next }
        { print }
    ' "$FALLBACK" > "$DEST" 2>/dev/null

    # 校验：插入成功且行数增加
    if [ -s "$DEST" ] && grep -q "zh-Hans" "$DEST" && grep -q "$TARGET_FONT" "$DEST"; then
        NEWLINES=$(wc -l < "$DEST")
        OLDLINES=$(wc -l < "$FALLBACK")
        if [ "$NEWLINES" -gt "$OLDLINES" ]; then
            ui_print "- 已在中文家族插入字体（$OLDLINES → $NEWLINES 行）"
        else
            ui_print "! 插入后行数未增加，放弃修改配置"
            rm -f "$DEST"
        fi
    else
        ui_print "! 配置里没有 zh-Hans/zh-Hant 家族，跳过（中文将保持系统默认）"
        rm -f "$DEST"
        rmdir "$MODPATH/system/etc" 2>/dev/null
    fi
else
    ui_print "! 没找到任何字体配置文件，只做文件覆盖（西文与 emoji 仍会生效）"
    rmdir "$MODPATH/system/etc" 2>/dev/null
fi

# ---------- 3. 结果汇总 ----------
ui_print " "
for f in "$MODPATH/system/fonts/"*; do
    [ -f "$f" ] && ui_print "- $(basename "$f")  $(( $(wc -c < "$f") / 1024 / 1024 )) MB"
done
ui_print " "
ui_print "- 安装完成，重启生效"
ui_print "- 若开不了机：开机时长按音量下键，进入 KSU 安全模式"
ui_print " "

set_perm_recursive "$MODPATH" 0 0 0755 0644 2>/dev/null
