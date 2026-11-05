#!/system/bin/sh
# 开机完成后跑一次（不驻留、不循环），做三件事：
#   1. 再清一遍 /data/fonts —— GMS 会在开机后重新下载字体包
#   2. 禁用 GMS 字体提供者，断掉重新下发的源头
#   3. 删掉 Skia / Minikin 的字形磁盘缓存，让系统重新解析字体
# 任何一步失败都不影响开机，最多是不生效。

MODDIR=${0%/*}
STATE=/data/adb/chiron_apple_emoji
LOG=$STATE/service.log
mkdir -p "$STATE"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG"; }

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

# ── 1. GMS 字体包 ────────────────────────────────────────────────────────────
if [ -d /data/fonts ]; then
  rm -rf /data/fonts
  log "removed /data/fonts (again)"
fi

# ── 2. 禁用 GMS 字体提供者 ───────────────────────────────────────────────────
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

# ── 3. 字形缓存 ──────────────────────────────────────────────────────────────
c=0
for f in /data/system/font_*.dat /data/system/font_*.log /data/misc/fonts/*; do
  [ -f "$f" ] || continue
  rm -f "$f" 2>/dev/null && c=$((c + 1))
done
log "cleared $c font cache files"

log "service.sh done"
exit 0
