#!/system/bin/sh
# 卸载时执行（Magisk / KernelSU 会在删除模块目录前把它交给系统跑一次）。
#
# 目的：把安装期间改过的东西逐项还原，不留「卸载完 Google 字体下载功能没了」的坑。
#   1. 按 disabled.list 把 GMS 字体服务逐个 enable 回来
#   2. 按 journal 把主题目录里的 emoji 字体还原成用户原来那一份
#   3. 把备份的 /data/fonts 放回去
#   4. 卸掉 /system/fonts 上的 bind mount（重启也会清，但立即生效更好）
#
# 任何一步失败都只写日志，不阻断卸载 —— 卸载不完整比卸不掉好。

MODDIR=${0%/*}
STATE=/data/adb/chiron_apple_emoji
LOG=$STATE/uninstall.log
DISABLED_LIST=$STATE/disabled.list
JOURNAL=$STATE/backup/journal.txt

mkdir -p "$STATE" 2>/dev/null
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG"; }

log "uninstall.sh start"

# ── 1. GMS 字体服务：按清单还原 ──────────────────────────────────────────────
PM=$(command -v pm)
if [ -s "$DISABLED_LIST" ] && [ -n "$PM" ]; then
  while IFS= read -r line; do
    case "$line" in
      user=*\ *)
        _u=${line%% *}
        _u=${_u#user=}
        _c=${line#* }
        case "$_u" in ''|*[!0-9]*) continue ;; esac
        if "$PM" enable --user "$_u" "$_c" >/dev/null 2>&1; then
          log "enabled user=$_u $_c"
        else
          log "FAILED enable user=$_u $_c"
        fi
        ;;
    esac
  done < "$DISABLED_LIST"
  mv -f "$DISABLED_LIST" "$DISABLED_LIST.done" 2>/dev/null
  log "gms restore done, list archived as disabled.list.done"
elif [ -s "$DISABLED_LIST" ]; then
  log "pm not found; kept $DISABLED_LIST for manual restore"
else
  log "no disabled.list, nothing to re-enable"
fi

# ── 2. 主题字体还原（journal 里记了原始文件与备份副本）───────────────────────
if [ -s "$JOURNAL" ]; then
  while IFS='|' read -r kind orig backup; do
    [ -n "$orig" ] || continue
    case "$kind" in
      file)
        if [ -f "$backup" ]; then
          if cp -f "$backup" "$orig" 2>/dev/null; then
            chmod 0644 "$orig" 2>/dev/null
            chown 1000:1000 "$orig" 2>/dev/null
            chcon u:object_r:system_file:s0 "$orig" 2>/dev/null
            log "restored file: $orig"
          else
            log "FAILED restore file: $orig (backup at $backup)"
          fi
        else
          log "backup missing for $orig"
        fi
        ;;
      dir)
        if [ -d "$backup" ] && [ ! -d "$orig" ]; then
          if mv "$backup" "$orig" 2>/dev/null; then
            log "restored dir: $orig"
          else
            log "FAILED restore dir: $orig (backup at $backup)"
          fi
        elif [ -d "$orig" ]; then
          log "skip dir restore (already exists): $orig"
        else
          log "backup missing for $orig"
        fi
        ;;
    esac
  done < "$JOURNAL"
  mv -f "$JOURNAL" "$JOURNAL.done" 2>/dev/null
else
  log "no journal, nothing to restore"
fi

# ── 3. 卸掉 bind mount / overlay ─────────────────────────────────────────────
# overlay 是挂在 /system/fonts 目录本身上的，先处理它，再处理单文件 bind。
# mountpoint 不是所有 Android 版本都有，退化成解析 mount 输出。
is_mounted() {
  _t=$1
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$_t" 2>/dev/null && return 0
    return 1
  fi
  mount 2>/dev/null | grep -F " $_t " >/dev/null 2>&1
}

if is_mounted /system/fonts; then
  umount -l /system/fonts 2>/dev/null && log "umounted overlay on /system/fonts"
fi
for T in /system/fonts/*[Ee]moji*.ttf; do
  [ -e "$T" ] || continue
  if is_mounted "$T"; then
    umount "$T" 2>/dev/null && log "umounted $T"
  fi
done

# ── 4. 清掉熔断标记，避免下次重装被上一轮的 overlay 记录挡住 ─────────────────
rm -f "$STATE/overlay_tried" "$STATE/overlay_confirmed" 2>/dev/null

log "uninstall.sh done"
log "备份仍保留在 $STATE/backup/（确认字体已还原后可手动删除）"
exit 0
