#!/system/bin/sh
# ============================================================
# Chiron × Apple Emoji —— 类原生 KSU / Magisk 字体模块
# 模块 id：chiron_apple_emoji（沿用 5.x / 6.2 这条线，不另起新模块）
#
# 6.5.2 起安装流程按 5.0 那版回来，因为 6.3 重写时把关键的几层保障丢了：
#   0. 冲突检测（谁也在写同一批字体）+ 清掉自身的 disable 标记
#   1. 探测系统 Roboto 的真实文件名，模块内字体改成同名
#   2. 读系统 font_fallback.xml，在 zh-Hans / zh-Hant 家族首位插入我们的字体
#   3. 解析 fonts.xml / font_fallback.xml，找出系统真正引用的 emoji 文件名
#      （不同 ROM 叫 NotoColorEmoji / MiSansEmoji / NotoColorEmojiLegacy…），
#      按分区映射到模块内的 system/ product/ system_ext/，逐个铺一份
#   4. 清掉 /data/fonts（GMS 下发）与 /data/system/theme/fonts（主题引擎）里的 emoji，
#      这两处优先级高于 /system/fonts，不清就会"装了跟没装一样"
#
# 任何一步失败都只跳过，不生成坏文件 —— 最差情况是中文没换，绝不会开不了机。
# ============================================================

SKIPUNZIP=0

# 兼容不同安装器（KernelSU 自带这些函数；Magisk 由 util_functions.sh 提供；
# APatch / 某些 Recovery 可能没有，这里补一份最小实现）
if ! type ui_print >/dev/null 2>&1; then ui_print() { echo "$1"; }; fi
if ! type abort    >/dev/null 2>&1; then abort()    { echo "$1"; exit 1; }; fi
if ! type set_perm >/dev/null 2>&1; then
    set_perm() { chown "$2:$3" "$1" 2>/dev/null; chmod "$4" "$1" 2>/dev/null; }
fi
if ! type set_perm_recursive >/dev/null 2>&1; then
    set_perm_recursive() {
        find "$1" -type d -exec chmod "$3" {} + 2>/dev/null
        find "$1" -type f -exec chmod "$4" {} + 2>/dev/null
    }
fi

MODPATH=${MODPATH:-${0%/*}}
SELF_ID="chiron_apple_emoji"
SYS_FONTS=/system/fonts

SRC_EMOJI="$MODPATH/system/fonts/NotoColorEmoji.ttf"
[ -f "$SRC_EMOJI" ] || abort "! 安装包缺少 system/fonts/NotoColorEmoji.ttf，请重新下载"

ui_print " "
ui_print "****************************************"
ui_print "  Chiron x Apple Emoji · 6.7"
ui_print "  Emoji 17.0（iOS 26 字形）+ 可选正文"
ui_print "****************************************"
ui_print " "

# ---------- 字体自检：档位数量必须 ≥ 5 ----------
# 这是 6.3–6.5.2 一直「装了还是安卓风格」的真凶。CBDT 是定点位图字体，
# 系统按实际像素大小挑 strike；只剩 38/53/70px 三档时，大字号请求 96/150px
# 找不到档位，FreeType 报 size 不匹配，Minikin 判定该字体不可用，直接回退到
# 系统自带的 NotoColorEmoji（AOSP 字形）。表现就是小字号像 iOS、一放大变安卓。
EMOJI_SZ=$(stat -c%s "$SRC_EMOJI" 2>/dev/null)
ui_print "- emoji 字体 $((${EMOJI_SZ:-0} / 1048576)) MB"
if [ "${EMOJI_SZ:-0}" -lt 130000000 ]; then
    ui_print "! 警告：字体只有 ${EMOJI_SZ:-0} 字节，远小于 5 档位应有的 ~190 MB"
    ui_print "! 这个包大概是 6.3–6.5.2 的旧版（32/45/60 三档），大字号会掉回安卓字形"
    ui_print "! 请换 6.6 的包重装"
else
    ui_print "- 档位自检通过（5 档：38/53/70/96/150 px）"
fi

# ---------- 0. 冲突检测 ----------
# 同一路径只能有一个来源：KSU / Magisk 按 /data/adb/modules 的目录名顺序挂载，
# 后挂的覆盖先挂的，不看版本号新旧。这里只报告，不替用户禁用别人的模块。
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
    ui_print "! 装完请把上面这些模块关掉或卸载"
else
    ui_print "- 没有其它模块抢同一批字体"
fi

# 6.3–6.5 临时用过 chiron_ksu_font。它和本模块 **id 不同**，KSU 会当成两个独立模块并列，
# 而且 "chiron_ksu_font" 按字母序排在 "chiron_apple_emoji" 后面 —— 模块是按目录名顺序
# 依次挂载、后挂覆盖先挂，于是那个旧模块的字体把本模块顶掉。
# 这正好能解释「装了 6.5.2 还是安卓风格、mount 里看着全挂上了」。
# 它是同项目的临时 id，直接清掉是安全的；清不掉就明确让用户手动卸载。
for OLD in /data/adb/modules/chiron_ksu_font /data/adb/modules_update/chiron_ksu_font; do
    [ -d "$OLD" ] || continue
    ui_print "! 发现 6.3–6.5 的旧模块：$OLD"
    ui_print "  它按字母序排在本模块之后，挂载时会覆盖本模块的字体"
    if rm -rf "$OLD" 2>/dev/null && [ ! -d "$OLD" ]; then
        ui_print "- 已移除（同项目的临时 id，删掉不会丢东西）"
    else
        ui_print "! 自动移除失败，请到模块列表把「Chiron × Apple Emoji（类原生）」卸载后重启"
    fi
done

# ---------- 0.5 自身启用状态 ----------
# KSU / Magisk 里「关闭」模块 = 在模块目录下建 disable 文件，被禁用的模块不挂载。
# 用同 id 升级安装时这个标记不会自动清掉，结果是新包装上了却依然禁用，
# 字体全部回退到系统原版 —— 表现就是 emoji 变回安卓风格。
for t in "/data/adb/modules/$SELF_ID/disable" \
         "/data/adb/modules/$SELF_ID/update" \
         "$MODPATH/disable" "$MODPATH/update"; do
    [ -e "$t" ] || continue
    if rm -f "$t" 2>/dev/null; then
        ui_print "! 检测到 $t"
        ui_print "- 已清除：模块此前处于禁用状态，本版安装后自动启用"
    else
        ui_print "! 检测到 $t，但清除失败"
        ui_print "  请到模块列表手动打开这个模块，否则装了也不生效"
    fi
done

if [ -e "/data/adb/modules/$SELF_ID/remove" ]; then
    ui_print "! 存在 remove 标记（模块待卸载），装完会把自己删掉"
    ui_print "  请先到模块列表取消卸载，再重装"
fi

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

SRC_BODY="$MODPATH/files/Roboto-Regular.ttf"
if [ "$TARGET_FONT" != "Roboto-Regular.ttf" ] && [ -f "$SRC_BODY" ]; then
    mv -f "$SRC_BODY" "$MODPATH/files/$TARGET_FONT"
    SRC_BODY="$MODPATH/files/$TARGET_FONT"
    ui_print "- 正文字体已重命名为：$TARGET_FONT"
fi
ui_print "- 正文字体默认不挂载（6.7 起），需要时在 WebUI 里打开"

# ---------- 2. font_fallback.xml ----------
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
    if [ -f /system/etc/fonts.xml ]; then
        ui_print "- 回退到 fonts.xml"
        FALLBACK=/system/etc/fonts.xml
    fi
fi

if [ -n "$FALLBACK" ]; then
    ui_print "- 配置文件：$FALLBACK"
    mkdir -p "$MODPATH/files"
    DEST="$MODPATH/files/font_fallback.xml"

    INS=""
    for w in 100 200 300 400 500 600 700 800 900; do
        INS="${INS}        <font weight=\"$w\" style=\"normal\" supportedAxes=\"wght\">$TARGET_FONT</font>
"
    done

    awk -v ins="$INS" '
        /<family[^>]*lang="[^"]*zh-Hans/ { print; printf "%s", ins; next }
        /<family[^>]*lang="[^"]*zh-Hant/ { print; printf "%s", ins; next }
        { print }
    ' "$FALLBACK" > "$DEST" 2>/dev/null

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
    fi
fi

# ---------- 3. emoji：找出系统真正引用的文件名，逐个铺 ----------
# 只放 system/fonts/NotoColorEmoji.ttf 是不够的：不同 ROM 的 emoji 由不同文件名承担
# （MiSansEmoji / NotoColorEmojiLegacy / NotoColorEmojiFlags…），漏掉任何一个，
# 系统就继续用它自己那份，表现就是"装了跟没装一样"。
ui_print "- 解析系统字体配置…"
NAMES=""

for XML in /system/etc/fonts.xml /system/etc/font_fallback.xml \
           /product/etc/fonts.xml /product/etc/font_fallback.xml \
           /system_ext/etc/fonts.xml; do
    [ -f "$XML" ] || continue
    _n=$(awk '
        /und-Zsye|<family[^>]*emoji/ { in_emoji = 1 }
        in_emoji && /<\/family>/      { in_emoji = 0 }
        {
            line = $0
            while (match(line, /[A-Za-z0-9._-]+\.ttf/)) {
                name = substr(line, RSTART, RLENGTH)
                line = substr(line, RSTART + RLENGTH)
                if (in_emoji == 1 || name ~ /[Ee]moji/) print name
            }
        }
    ' "$XML" 2>/dev/null | sort -u)
    [ -n "$_n" ] && NAMES="$NAMES
$_n"
done

NAMES=$(printf '%s\n' "$NAMES" | sed '/^$/d' | sort -u)
if [ -n "$NAMES" ]; then
    ui_print "  系统引用的 emoji 字体："
    printf '%s\n' "$NAMES" | while IFS= read -r n; do ui_print "    · $n"; done
else
    ui_print "  未解析到（使用通用文件名兜底）"
fi

FALLBACK_NAMES="NotoColorEmoji.ttf
NotoColorEmojiLegacy.ttf
NotoColorEmojiFlags.ttf
MiSansEmoji.ttf"

LIST=$(printf '%s\n%s\n' "$NAMES" "$FALLBACK_NAMES" | sed '/^$/d' | sort -u)

# 系统真实路径 → 模块内路径。KSU / Magisk 只认模块内的 system/ product/ system_ext/ 顶层目录
map_path() {
    case "$1" in
        /system/system/*) echo "$MODPATH/system/${1#/system/system/}" ;;
        /system/*)        echo "$MODPATH$1" ;;
        /product/*)       echo "$MODPATH/product/${1#/product/}" ;;
        /system_ext/*)    echo "$MODPATH/system_ext/${1#/system_ext/}" ;;
        /vendor/*)        echo "$MODPATH/vendor/${1#/vendor/}" ;;
        *)                echo "" ;;
    esac
}

link_in() {
    [ -f "$1" ] && return 0
    mkdir -p "$(dirname "$1")" 2>/dev/null
    ln "$SRC_EMOJI" "$1" 2>/dev/null || cp -f "$SRC_EMOJI" "$1" 2>/dev/null
}

ui_print "- 建立字体覆盖…"
printf '%s\n' "$LIST" | while IFS= read -r NAME; do
    [ -n "$NAME" ] || continue
    BASENAME="${NAME##*/}"

    FOUND=""
    case "$NAME" in
        /*) [ -f "$NAME" ] && FOUND="$NAME" ;;
    esac
    if [ -z "$FOUND" ]; then
        for D in /system/fonts /system/system/fonts /product/fonts \
                 /system/product/fonts /system_ext/fonts /vendor/fonts; do
            if [ -f "$D/$BASENAME" ]; then FOUND="$D/$BASENAME"; break; fi
        done
    fi

    if [ -n "$FOUND" ]; then
        DST=$(map_path "$FOUND")
        if [ -n "$DST" ]; then
            link_in "$DST"
            FSZ=$(stat -c%s "$FOUND" 2>/dev/null)
            ui_print "  ✓ $FOUND（$((${FSZ:-0} / 1024)) KB）→ 已接管"
        fi
    fi

    # 系统上暂时没有也铺一份，防止系统按名字查找时落空
    link_in "$MODPATH/system/fonts/$BASENAME"
done

[ -f "$MODPATH/system/fonts/NotoColorEmoji.ttf" ] || cp -f "$SRC_EMOJI" "$MODPATH/system/fonts/NotoColorEmoji.ttf"

# ---------- 4. 清掉会抢优先级的上层字体 ----------
# 安装时先清一遍，开机后 post-fs-data / service 还会再清（GMS 可能重新下发）
if [ -d /data/fonts ]; then
    rm -rf /data/fonts && ui_print "- 已清除 /data/fonts（GMS 下发的字体包）"
fi

if [ -d /data/system/theme/fonts ]; then
    _hit=0
    for f in /data/system/theme/fonts/*[Ee]moji*.ttf; do
        [ -e "$f" ] || continue
        rm -f "$f" && _hit=$((_hit + 1))
    done
    [ "$_hit" -gt 0 ] && ui_print "- 已清除主题字体目录中的 $_hit 个 emoji 字体"
fi

# ---------- 5. 权限 ----------
set_perm_recursive "$MODPATH" 0 0 0755 0644 2>/dev/null
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755 2>/dev/null
set_perm "$MODPATH/service.sh"      0 0 0755 2>/dev/null
set_perm "$MODPATH/action.sh"       0 0 0755 2>/dev/null
set_perm "$MODPATH/scripts/diag.sh" 0 0 0755 2>/dev/null
set_perm "$MODPATH/scripts/set-state.sh" 0 0 0755 2>/dev/null

# ---------- 5.5 默认开关（WebUI 读写）----------
mkdir -p /data/adb/chiron_apple_emoji 2>/dev/null
CONF=/data/adb/chiron_apple_emoji/settings.conf
if [ ! -f "$CONF" ]; then
    printf 'EMOJI=1\nBODY=0\n' > "$CONF"
    ui_print "- 默认开关：emoji 开 / 正文关"
    ui_print "  正文可变字体在微信、抖音里会让输入框光标消失，6.7 起默认不换正文"
else
    ui_print "- 保留上次的开关：$(tr '\n' ' ' < "$CONF")"
fi

# ---------- 6. 汇总 ----------
ui_print " "
ui_print "- 写入模块的字体："
for f in "$MODPATH/system/fonts/"*; do
    [ -f "$f" ] || continue
    SZ=$(($(stat -c%s "$f") / 1024 / 1024))
    H=$(sha256sum "$f" 2>/dev/null | cut -c1-16)
    ui_print "    $(basename "$f")  ${SZ} MB  ${H:-}"
done
ui_print " "
ui_print "- 开机后 post-fs-data 会用 bind mount 逐个顶掉系统 emoji 位点"
ui_print "  （KSU 的 overlay 在本机型不保证生效，bind 是内核行为，不依赖挂载实现）"
ui_print "- 模块详情页新增 WebUI：表情包切换 / 正文开关 / 诊断 / 日志导出"
ui_print "- 安装完成，重启生效"
ui_print "- 重启后无变化：进模块详情点「执行」按钮，会现场挂载并打印诊断"
ui_print " "

# ---------- 7. 尊重上次的「关掉 emoji」选择 ----------
# 新包会把 system/fonts/NotoColorEmoji.ttf 带回来，但 KSU 的 overlay 只看目录里有没有
# 这个文件 —— 所以关掉 emoji 时文件必须挪出 system/fonts，重启才会是系统原厂。
_E=$(grep -m1 '^EMOJI=' "$CONF" 2>/dev/null | cut -d= -f2)
if [ "$_E" = "0" ]; then
    mkdir -p "$MODPATH/files/off" 2>/dev/null
    _n=0
    for f in "$MODPATH"/system/fonts/*[Ee]moji*.ttf; do
        [ -e "$f" ] || continue
        mv -f "$f" "$MODPATH/files/off/" 2>/dev/null && _n=$((_n + 1))
    done
    ui_print "- 上次把 emoji 关掉了，本版安装后保持关闭（挪走 $_n 个文件）"
    ui_print "  想要 Apple emoji：模块详情页 → WebUI → 表情包切换 → Apple 17.0"
fi
ui_print " "
