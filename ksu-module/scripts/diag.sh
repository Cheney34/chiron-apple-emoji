#!/system/bin/sh
# 诊断：一次说清"模块到底有没有生效"。
# 输出同时给 stdout（KernelSU 执行按钮里直接看）和 /sdcard/emoji_diag.txt。

OUT=${1:-/sdcard/emoji_diag.txt}

# 本脚本在 scripts/ 下，MODDIR 是模块根目录
MODDIR=$(cd "${0%/*}/.." 2>/dev/null && pwd)
[ -n "$MODDIR" ] || MODDIR=${0%/*}/..
STATE=/data/adb/chiron_apple_emoji

EMOJI_SRC=$MODDIR/system/fonts/NotoColorEmoji.ttf
EMOJI_SZ=$(stat -c%s "$EMOJI_SRC" 2>/dev/null)

BODY_SRC=""
for f in "$MODDIR"/system/fonts/Roboto*; do
    [ -f "$f" ] || continue
    BODY_SRC="$f"
    break
done

: > "$OUT" 2>/dev/null || OUT=/data/local/tmp/emoji_diag.txt

say() { printf '%s\n' "$1" | tee -a "$OUT"; }
hdr() { say ""; say "===== $1 ====="; }
dump() {
    [ -f "$1" ] || { say "  (无)"; return; }
    while IFS= read -r L; do say "  $L"; done < "$1"
}

hdr "设备"
say "厂商: $(getprop ro.product.manufacturer)"
say "型号: $(getprop ro.product.model)"
say "系统: Android $(getprop ro.build.version.release) / API $(getprop ro.build.version.sdk)"
say "ROM : $(getprop ro.mi.os.version.name)$(getprop ro.miui.ui.version.name)$(getprop ro.build.version.incremental)"
say "时间: $(date)"
say "内核: $(uname -r)"
say "system 挂载: $(mount 2>/dev/null | awk '$3=="/system"||$2=="/system"{print $5; exit}')"

hdr "模块身份"
if [ -f "$MODDIR/module.prop" ]; then
    grep -E '^(id|name|version|versionCode)=' "$MODDIR/module.prop" | while IFS= read -r L; do say "  $L"; done
fi
say "模块目录: $MODDIR"
if [ -e "$MODDIR/disable" ]; then
    say "  !! 模块目录下有 disable 标记，模块处于禁用状态 —— 这就是不生效的原因"
else
    say "  disable 标记：无（正常）"
fi
if [ -d /data/adb/modules/chiron_ksu_font ]; then
    say "  !! 还留着 6.3–6.5 的 chiron_ksu_font，两个模块会抢同一批字体，建议卸载"
fi

hdr "模块字体"
say "emoji: $EMOJI_SRC"
say "       字节数 $EMOJI_SZ"
say "       指纹   $(sha256sum "$EMOJI_SRC" 2>/dev/null | cut -c1-16)"
if [ -n "$BODY_SRC" ]; then
    say "正文 : $(basename "$BODY_SRC")  $(stat -c%s "$BODY_SRC" 2>/dev/null) 字节"
    say "       指纹 $(sha256sum "$BODY_SRC" 2>/dev/null | cut -c1-16)"
else
    say "正文 : 缺失"
fi

hdr "系统 emoji 字体位点"
FOUND=0
for d in /system/fonts /system/system/fonts /product/fonts /system/product/fonts /system_ext/fonts /vendor/fonts; do
    [ -d "$d" ] || continue
    for f in "$d"/*[Ee]moji*.ttf; do
        [ -e "$f" ] || continue
        FOUND=1
        SZ=$(stat -c%s "$f" 2>/dev/null)
        if [ "$SZ" = "$EMOJI_SZ" ]; then
            say "  [已接管] $f  ${SZ} 字节"
        else
            say "  [未接管] $f  ${SZ} 字节  <-- 系统在用这份"
        fi
    done
done
[ "$FOUND" -eq 0 ] && say "  未在系统目录找到任何 emoji 字体（异常）"

hdr "正文位点"
if [ -n "$BODY_SRC" ]; then
    BT="/system/fonts/$(basename "$BODY_SRC")"
    if [ -f "$BT" ]; then
        SZ=$(stat -c%s "$BT" 2>/dev/null)
        A=$(stat -c%s "$BODY_SRC" 2>/dev/null)
        if [ "$SZ" = "$A" ]; then
            say "  [已接管] $BT  ${SZ} 字节"
        else
            say "  [未接管] $BT  ${SZ} 字节（模块内 $A）"
        fi
    else
        say "  $BT 不存在"
    fi
fi

hdr "当前挂载（看 emoji 是否被 bind 上）"
mount 2>/dev/null | grep -i 'moji' | head -12 > /tmp/_lf
dump /tmp/_lf

hdr "/data/fonts（GMS 下发的字体包，优先级高于 /system）"
if [ -d /data/fonts ]; then
    say "  存在，内容："
    find /data/fonts -maxdepth 3 2>/dev/null | head -20 > /tmp/_lf
    dump /tmp/_lf
else
    say "  不存在（正常）"
fi

hdr "/data/system/theme/fonts（主题引擎解包目录）"
if [ -d /data/system/theme/fonts ]; then
    ls -l /data/system/theme/fonts 2>/dev/null | awk 'NR>1 {print $5"  "$9}' > /tmp/_lf
    dump /tmp/_lf
else
    say "  不存在"
fi

hdr "fonts.xml 中的 emoji 家族"
for X in /system/etc/fonts.xml /system/etc/font_fallback.xml /product/etc/fonts.xml; do
    [ -f "$X" ] || continue
    say "--- $X ($(wc -l < "$X") 行)"
    grep -n -A3 'und-Zsye' "$X" 2>/dev/null | head -16 > /tmp/_lf
    dump /tmp/_lf
done

hdr "开机脚本记录"
say "--- post-fs.log"
dump "$STATE/post-fs.log"
say "--- service.log"
dump "$STATE/service.log"

hdr "结论"
OURS=0
TOTAL=0
for f in /system/fonts/*[Ee]moji*.ttf; do
    [ -e "$f" ] || continue
    TOTAL=$((TOTAL + 1))
    [ "$(stat -c%s "$f" 2>/dev/null)" = "$EMOJI_SZ" ] && OURS=$((OURS + 1))
done
if [ -e "$MODDIR/disable" ]; then
    say "  模块被禁用（disable 标记）。到模块列表打开它，或重装 6.5.2+（安装时会自动清掉）。"
elif [ "$TOTAL" -eq 0 ]; then
    say "  系统里找不到任何 emoji 字体文件，ROM 结构异常。"
elif [ "$OURS" -eq "$TOTAL" ]; then
    say "  全部 $TOTAL 个 emoji 位点已接管（Apple emoji 生效）。"
    say "  若仍有界面显示安卓表情，那是该 App 自带图片，与字体无关。"
elif [ "$OURS" -gt 0 ]; then
    say "  部分接管（$OURS/$TOTAL）：见上面标 [未接管] 的文件。"
else
    say "  一个都没接管（0/$TOTAL）：bind mount 未成功。"
    say "  重点看 post-fs.log 里的 bind FAILED 行，把本文件发回给开发者。"
fi

say ""
say "日志：$OUT"
rm -f /tmp/_lf
