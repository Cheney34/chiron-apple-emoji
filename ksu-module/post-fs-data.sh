#!/system/bin/sh
# post-fs-data：KSU / Magisk 的 magic mount 已在此阶段之前完成
# 这里只记录结果，不改任何东西 —— 排查问题时看 /data/local/tmp/chiron_font.log

LOG=/data/local/tmp/chiron_font.log

{
    echo "=== $(date) chiron_ksu_font ==="
    echo

    echo "[字体文件]"
    for f in /system/fonts/Roboto-Regular.ttf /system/fonts/NotoColorEmoji.ttf; do
        if [ -f "$f" ]; then
            echo "  $(wc -c < "$f") bytes  $f"
        else
            echo "  缺失  $f"
        fi
    done

    echo
    echo "[所有 Roboto 文件]"
    ls /system/fonts/ 2>/dev/null | grep -i '^Roboto' | while read -r n; do
        echo "  $(wc -c < "/system/fonts/$n") bytes  $n"
    done

    echo
    echo "[中文家族首位字体]"
    if [ -f /system/etc/font_fallback.xml ]; then
        awk '/zh-Hans/ { if (!done) { found=1 } }
             found && /<font/ { print "  " $0; done=1; exit }' \
            /system/etc/font_fallback.xml 2>/dev/null || echo "  解析失败"
    else
        echo "  /system/etc/font_fallback.xml 不存在"
    fi

    echo
    echo "[L2 通道检查]"
    if [ -d /data/fonts ] && [ -n "$(ls -A /data/fonts 2>/dev/null)" ]; then
        echo "  警告：/data/fonts 非空，GMS 下发的字体会覆盖本模块"
        ls -l /data/fonts 2>/dev/null
    else
        echo "  /data/fonts 为空，无冲突"
    fi
} > "$LOG" 2>&1

chmod 0644 "$LOG" 2>/dev/null
