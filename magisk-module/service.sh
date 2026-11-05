#!/system/bin/sh
# 开机完成后跑一次（不驻留、不循环），做三件事：
#   1. 把 GMS 重新下发的 /data/fonts 挪进备份（不删，可还原）
#   2. 禁用 GMS 字体提供者，断掉重新下发的源头；禁了哪些记进 disabled.list
#   3. 删掉 Skia / Minikin 的字形磁盘缓存，让系统重新解析字体
# 任何一步失败都不影响开机，最多是不生效。
# 卸载时 uninstall.sh 会按 disabled.list 把 GMS 组件逐个 enable 回来。

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

# 能走到这里说明这次开机没被我们的挂载搞崩 —— 给 overlay 兜底留个"存活证明"。
# post-fs-data.sh 靠 overlay_tried / overlay_confirmed 这对标记做死循环熔断。
if [ -f "$STATE/overlay_tried" ] && [ ! -f "$STATE/overlay_confirmed" ]; then
  : > "$STATE/overlay_confirmed"
  log "overlay attempt survived boot -> confirmed"
fi

# 等 /sdcard 就绪
j=0
while [ ! -d /sdcard ] && [ "$j" -lt 60 ]; do sleep 1; j=$((j + 1)); done

# ── 1. GMS 字体包（挪进备份，不再 rm -rf）─────────────────────────────────────
stash_fonts() {
  [ -d /data/fonts ] || { log "/data/fonts absent"; return 0; }
  _bk=$STATE/backup/gms-$(date +%Y%m%d-%H%M%S)
  if ! mkdir -p "$_bk" 2>/dev/null; then
    log "backup dir create failed, skip (left /data/fonts in place)"
    return 1
  fi
  if mv /data/fonts "$_bk/data-fonts" 2>/dev/null; then
    log "stashed /data/fonts -> $_bk/data-fonts"
  else
    log "failed to stash /data/fonts, left in place"
    return 1
  fi
  # 只保留最近 2 份 GMS 备份，避免每次开机堆一份（GMS 会反复重新下发）
  ls -dt "$STATE"/backup/gms-* 2>/dev/null | tail -n +3 | while IFS= read -r _old; do
    rm -rf "$_old" 2>/dev/null
    log "pruned old gms backup: ${_old##*/}"
  done
  return 0
}
stash_fonts

# ── 2. 禁用 GMS 字体提供者（禁了什么就记什么，卸载时按清单还原）──────────────
# 原实现只 disable 不记录、无 uninstall.sh，卸载后 Google 字体下载功能永久消失。
# 现在每成功禁用一项就写一行 disabled.list，uninstall.sh 逐行 enable 回去。
DISABLED_LIST=$STATE/disabled.list

record_disabled() {
  # $1 = "user=<uid> <component>"
  grep -qxF "$1" "$DISABLED_LIST" 2>/dev/null || echo "$1" >> "$DISABLED_LIST"
}

PM=$(command -v pm)
if [ -n "$PM" ]; then
  _hit=0
  for UP in /data/user/*; do
    [ -d "$UP" ] || continue
    UID_=${UP##*/}
    case "$UID_" in ''|*[!0-9]*) continue ;; esac
    for COMP in \
      com.google.android.gms/com.google.android.gms.fonts.provider.FontsProvider \
      com.google.android.gms/com.google.android.gms.fonts.update.UpdateSchedulerService
    do
      if "$PM" disable --user "$UID_" "$COMP" >/dev/null 2>&1; then
        record_disabled "user=$UID_ $COMP"
        _hit=$((_hit + 1))
      fi
    done
  done
  log "gms font provider disabled ($_hit entries, list=$DISABLED_LIST)"
  [ -s "$DISABLED_LIST" ] && log "uninstall.sh will re-enable $(wc -l < "$DISABLED_LIST") entries"
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
