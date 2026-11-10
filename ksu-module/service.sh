#!/system/bin/sh
# 开机完成后跑一次（不驻留、不循环），做四件事：
#   1. 再清一遍 /data/fonts —— GMS 会在开机后重新下载字体包
#   2. 再替换一遍主题字体目录里的 emoji —— 主题引擎可能在开机后重新解包
#   3. 禁用 GMS 字体提供者，断掉重新下发的源头
#   4. 删掉 Skia / Minikin 的字形磁盘缓存，让系统重新解析字体
# 任何一步失败都不影响开机，最多是不生效。

MODDIR=${0%/*}
STATE=/data/adb/chiron_apple_emoji
LOG=$STATE/service.log
EMOJI_SRC="$MODDIR/system/fonts/NotoColorEmoji.ttf"
mkdir -p "$STATE"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG"; }

: > "$LOG"
log "service.sh start"

# 等开机完成，最多 120 秒
i=0
while [ "$i" -lt 120 ]; do
    [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
    sleep 2
    i=$((i + 2))
done
log "boot_completed after ${i}s"

# 等 /sdcard 就绪
j=0
while [ ! -d /sdcard ] && [ "$j" -lt 60 ]; do sleep 1; j=$((j + 1)); done

EMOJI_SZ=$(stat -c%s "$EMOJI_SRC" 2>/dev/null)

# WebUI 开关：EMOJI=0 表示用户选了系统原厂 emoji，模块不再插手
EMOJI_ON=1
CONF=$STATE/settings.conf
[ -f "$CONF" ] && . "$CONF" 2>/dev/null
case "$EMOJI_ON" in 0|1) ;; *) EMOJI_ON=1 ;; esac
log "settings: EMOJI=$EMOJI_ON"

# ── 1. GMS 字体包 ────────────────────────────────────────────────────────────
if [ -d /data/fonts ]; then
    rm -rf /data/fonts
    log "removed /data/fonts (again)"
fi

# ── 2. 主题字体目录 ──────────────────────────────────────────────────────────
if [ -d /data/system/theme/fonts ] && [ -f "$EMOJI_SRC" ] && [ "$EMOJI_ON" = "1" ]; then
    n=0
    for f in /data/system/theme/fonts/*[Ee]moji*.ttf; do
        [ -e "$f" ] || continue
        [ "$(stat -c%s "$f" 2>/dev/null)" = "$EMOJI_SZ" ] && continue
        cp -f "$EMOJI_SRC" "$f" 2>/dev/null && {
            chmod 0644 "$f" 2>/dev/null
            chown 1000:1000 "$f" 2>/dev/null
            chcon u:object_r:system_file:s0 "$f" 2>/dev/null
            n=$((n + 1))
        }
    done
    log "theme: replaced $n emoji font(s)"
fi

# ── 3. 禁用 GMS 字体提供者 ───────────────────────────────────────────────────
PM=$(command -v pm)
if [ -n "$PM" ]; then
    for UP in /data/user/*; do
        [ -d "$UP" ] || continue
        UID_=${UP##*/}
        "$PM" disable --user "$UID_" com.google.android.gms/com.google.android.gms.fonts.provider.FontsProvider >/dev/null 2>&1
        "$PM" disable --user "$UID_" com.google.android.gms/com.google.android.gms.fonts.update.UpdateSchedulerService >/dev/null 2>&1
    done
    log "gms font provider disabled"
else
    log "pm not found, skip"
fi

# ── 4. 字形缓存 ──────────────────────────────────────────────────────────────
c=0
for f in /data/system/font_*.dat /data/system/font_*.log /data/misc/fonts/*; do
    [ -f "$f" ] || continue
    rm -f "$f" 2>/dev/null && c=$((c + 1))
done
log "cleared $c font cache files"

# ── 5. 最后再确认一次：还有位点没接管就补 bind ───────────────────────────────
if [ -f "$EMOJI_SRC" ] && [ "$EMOJI_ON" = "1" ]; then
    miss=0
    for T in /system/fonts/*[Ee]moji*.ttf /product/fonts/*[Ee]moji*.ttf \
             /system_ext/fonts/*[Ee]moji*.ttf; do
        [ -e "$T" ] || continue
        if [ "$(stat -c%s "$T" 2>/dev/null)" != "$EMOJI_SZ" ]; then
            miss=$((miss + 1))
            if mount --bind "$EMOJI_SRC" "$T" 2>>"$LOG"; then
                log "late bind OK: $T"
            else
                log "late bind FAILED: $T"
            fi
        fi
    done
    log "late check done, $miss 位点需要补挂"
fi

log "service.sh done"
exit 0
