#!/system/bin/sh
# KernelSU / Magisk 模块详情页的「执行」按钮。
# 现场做一次 bind mount + 清缓存 + 诊断，不用重启就知道成不成。

MODDIR=${0%/*}
EMOJI_SRC=$MODDIR/system/fonts/NotoColorEmoji.ttf
EMOJI_SZ=$(stat -c%s "$EMOJI_SRC" 2>/dev/null)

BODY_SRC=""
for f in "$MODDIR"/system/fonts/Roboto*; do
    [ -f "$f" ] || continue
    BODY_SRC="$f"
    break
done

echo ""
echo "===== Chiron × Apple Emoji · 一键修复 ====="
echo ""

# 0. SELinux 上下文
for f in "$EMOJI_SRC" "$BODY_SRC"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if chcon u:object_r:system_file:s0 "$f" 2>/dev/null; then
        echo "OK  $(basename "$f") 上下文已设为 system_file"
    else
        echo "--  $(basename "$f") chcon 失败（继续尝试）"
    fi
done

# 1. GMS 可更新字体
if [ -d /data/fonts ]; then
    rm -rf /data/fonts
    echo "OK  已删除 /data/fonts（GMS 字体包）"
else
    echo "--  /data/fonts 不存在"
fi

# 2. 主题字体目录里的 emoji
n=0
if [ -d /data/system/theme/fonts ]; then
    for f in /data/system/theme/fonts/*[Ee]moji*.ttf; do
        [ -e "$f" ] || continue
        [ "$(stat -c%s "$f" 2>/dev/null)" = "$EMOJI_SZ" ] && continue
        cp -f "$EMOJI_SRC" "$f" 2>/dev/null && n=$((n + 1))
    done
fi
echo "OK  主题字体目录替换 $n 个 emoji 字体"

# 3. bind mount emoji
echo ""
echo "--- 挂载 emoji 字体 ---"
bound=0
for T in /system/fonts/*[Ee]moji*.ttf /product/fonts/*[Ee]moji*.ttf \
         /system_ext/fonts/*[Ee]moji*.ttf; do
    [ -e "$T" ] || continue
    CUR=$(stat -c%s "$T" 2>/dev/null)
    if [ "$CUR" = "$EMOJI_SZ" ]; then
        echo "  跳过（已是我们的）: $T"
        continue
    fi
    if mount --bind "$EMOJI_SRC" "$T" 2>/dev/null || mount -o bind "$EMOJI_SRC" "$T" 2>/dev/null; then
        echo "  成功: $T  $CUR -> $(stat -c%s "$T" 2>/dev/null)"
        bound=$((bound + 1))
    else
        echo "  失败: $T  (当前 $CUR 字节)"
    fi
done
echo "  合计 $bound 个位点已挂载"

# 4. 正文字体
if [ -n "$BODY_SRC" ] && [ -f "$BODY_SRC" ]; then
    BT="/system/fonts/$(basename "$BODY_SRC")"
    if [ -f "$BT" ]; then
        A=$(stat -c%s "$BODY_SRC")
        B=$(stat -c%s "$BT")
        if [ "$A" = "$B" ]; then
            echo "OK  正文字体已是模块内那份"
        elif mount --bind "$BODY_SRC" "$BT" 2>/dev/null; then
            echo "OK  正文字体已挂载: $B -> $(stat -c%s "$BT" 2>/dev/null)"
        else
            echo "!!  正文字体挂载失败: $BT"
        fi
    fi
fi

# 5. 字形缓存
c=0
for f in /data/system/font_*.dat /data/system/font_*.log; do
    [ -f "$f" ] || continue
    rm -f "$f" 2>/dev/null && c=$((c + 1))
done
echo "OK  清除 $c 个字形缓存文件"

echo ""
echo "--- 诊断 ---"
sh "$MODDIR/scripts/diag.sh" /sdcard/emoji_diag.txt

echo ""
if [ "$bound" -gt 0 ]; then
    echo "已挂载完成。字体服务已缓存旧字体，需重启一次才能看到效果。"
else
    echo "全部位点都已是本模块字体，无需再挂载。"
    echo "若显示仍旧，说明该 App 自己画表情，与字体无关。"
fi
echo "======================================="
