#!/system/bin/sh
# 开机早期（/data 已挂载、zygote 未起）执行，四件事：
#   1. 把会抢优先级的 /data/fonts（GMS 下发）挪进备份，并覆盖主题字体目录里的 emoji
#   2. 用 bind mount 把 Apple emoji 顶到 /system/fonts 的每个 emoji 位点
#   3. 修 SELinux 上下文，否则 system_server 读不到
#   4. 全量写日志，便于下次定位
#
# 为什么不用模块自带的 system/ overlay：
#   本机（25113PN0EC / Android 17 / HyperOS 4.0）实测 overlay 未生效，
#   /system/fonts/NotoColorEmoji.ttf 仍是原厂 2992136 字节。
#   bind mount 是内核行为，不依赖 KSU 的挂载实现，只要 su 有 CAP_SYS_ADMIN 就成立。

MODDIR=${0%/*}
STATE=/data/adb/chiron_apple_emoji
LOG=$STATE/post-fs.log
SRC=$MODDIR/system/fonts/NotoColorEmoji.ttf

mkdir -p "$STATE"
: > "$LOG"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG"; }

log "post-fs-data start (mod=$MODDIR)"
[ -f "$SRC" ] || { log "FATAL: source font missing"; exit 0; }
SRC_SZ=$(stat -c%s "$SRC" 2>/dev/null)
log "source: ${SRC_SZ} bytes"

# ── 1. GMS 可更新字体（挪进备份，不再 rm -rf）────────────────────────────────
if [ -d /data/fonts ]; then
  _bk=$STATE/backup/gms-$(date +%Y%m%d-%H%M%S)
  if mkdir -p "$_bk" 2>/dev/null && mv /data/fonts "$_bk/data-fonts" 2>/dev/null; then
    log "stashed /data/fonts -> $_bk/data-fonts"
    echo "dir|/data/fonts|$_bk/data-fonts" >> "$STATE/backup/journal.txt"
    # 只保留最近 2 份，避免每次开机堆一份
    ls -dt "$STATE"/backup/gms-* 2>/dev/null | tail -n +3 | while IFS= read -r _old; do
      rm -rf "$_old" 2>/dev/null
    done
  else
    log "failed to stash /data/fonts, left in place"
  fi
else
  log "/data/fonts absent"
fi

# ── 2. 主题引擎字体目录 ──────────────────────────────────────────────────────
THEME_FONTS=/data/system/theme/fonts
if [ -d "$THEME_FONTS" ]; then
  n=0
  for f in "$THEME_FONTS"/*[Ee]moji*.ttf; do
    [ -e "$f" ] || continue
    CUR=$(stat -c%s "$f" 2>/dev/null)
    [ "$CUR" = "$SRC_SZ" ] && continue
    # 覆盖前先备份一次（每个文件只备第一次，保留用户原始的那一份）
    _name=$(basename "$f")
    _bkdir=$STATE/backup/theme
    mkdir -p "$_bkdir" 2>/dev/null
    if [ ! -f "$_bkdir/$_name" ]; then
      if ! cp -p "$f" "$_bkdir/$_name" 2>/dev/null; then
        log "theme: backup failed for $_name, left untouched"
        continue
      fi
      echo "file|$f|$_bkdir/$_name" >> "$STATE/backup/journal.txt"
      log "theme: backed up $_name ($CUR bytes)"
    fi
    cp -f "$SRC" "$f" 2>/dev/null && {
      chmod 0644 "$f" 2>/dev/null
      chown 1000:1000 "$f" 2>/dev/null
      chcon u:object_r:system_file:s0 "$f" 2>/dev/null
      log "theme: replaced $(basename "$f") ($CUR -> $SRC_SZ)"
      n=$((n + 1))
    }
  done
  [ "$n" -eq 0 ] && log "theme: no emoji font to replace"
else
  log "theme dir absent"
fi

# ── 3. SELinux 上下文 ────────────────────────────────────────────────────────
# 模块目录里的文件默认是 magisk_file / ksu_file 标签，
# system_server 没读权限，bind 过去也加载失败。必须改成系统字体标签。
if chcon u:object_r:system_file:s0 "$SRC" 2>/dev/null; then
  log "chcon: ok"
elif restorecon "$SRC" 2>/dev/null; then
  log "restorecon: ok"
else
  log "chcon failed (will try anyway)"
fi
log "context: $(ls -Z "$SRC" 2>/dev/null | awk '{print $1}')"

# ── 4. bind mount 到每个 emoji 位点 ──────────────────────────────────────────
# HyperOS 4 的 emoji 由三个文件分担：
#   NotoColorEmojiLegacy.ttf（ignore=true，旧版兼容）
#   NotoColorEmoji.ttf（主）
#   NotoColorEmojiFlags.ttf（旗帜）
# 全部顶掉，否则会出现"人脸变了但国旗还是安卓"的半吊子状态。
bound=0
for T in /system/fonts/*[Ee]moji*.ttf; do
  [ -e "$T" ] || continue
  CUR=$(stat -c%s "$T" 2>/dev/null)
  if [ "$CUR" = "$SRC_SZ" ]; then
    log "skip (already ours): $T"
    continue
  fi
  if mount --bind "$SRC" "$T" 2>>"$LOG"; then
    NEW=$(stat -c%s "$T" 2>/dev/null)
    log "bind OK: $T  $CUR -> $NEW"
    bound=$((bound + 1))
  else
    # 退一步：-o bind 写法
    if mount -o bind "$SRC" "$T" 2>>"$LOG"; then
      log "bind OK(-o): $T -> $(stat -c%s "$T" 2>/dev/null)"
      bound=$((bound + 1))
    else
      log "bind FAILED: $T"
    fi
  fi
done
log "bind summary: $bound mounted"

# ── 4b. overlayfs 兜底（默认关闭，必须显式开启）───────────────────────────────
# 为什么默认关：
#   upperdir 里字体的 SELinux 标签是 magisk_file / ksu_file，system_server 读不到；
#   原实现的回滚探测只看「基础字体文件非空」，不看能否真正加载。
#   一旦挂上又加载失败，表现是 SystemUI 循环崩溃，而且下次开机还会再挂一次 → 死循环。
#
# 现在的规则：
#   · 用户手动 `touch /data/adb/chiron_apple_emoji/enable_overlay` 才尝试；
#   · 挂上并通过探测后写 overlay_tried；开机完成由 service.sh 写 overlay_confirmed；
#     下次开机若发现「tried 有、confirmed 没有」，说明上次没熬过开机 → 永久停用（熔断）；
#   · 探测必须同时满足「基础字体可读」「ttf 数量正常」「emoji 已是我们的」，否则立即 umount -l。
if [ "$bound" -eq 0 ]; then
  if [ ! -f "$STATE/enable_overlay" ]; then
    log "no bind succeeded; overlay fallback is OFF by default"
    log "  -> 如需尝试：touch $STATE/enable_overlay 后重启"
  elif [ -f "$STATE/overlay_tried" ] && [ ! -f "$STATE/overlay_confirmed" ]; then
    log "overlay was attempted last boot but never reached boot_completed"
    log "  -> overlay permanently disabled to avoid a boot loop"
    log "  -> 排查后删除 $STATE/overlay_tried 可重新尝试"
  else
    log "trying overlayfs (opt-in)"
    UPPER=$STATE/ovl_upper
    WORK=$STATE/ovl_work
    rm -rf "$WORK"
    mkdir -p "$UPPER" "$WORK"
    cp -f "$SRC" "$UPPER/NotoColorEmoji.ttf" 2>/dev/null || log "copy to upper failed"
    chcon u:object_r:system_file:s0 "$UPPER/NotoColorEmoji.ttf" 2>/dev/null
    chmod 0644 "$UPPER/NotoColorEmoji.ttf" 2>/dev/null

    if mount -t overlay overlay -o "lowerdir=/system/fonts,upperdir=$UPPER,workdir=$WORK" /system/fonts 2>>"$LOG"; then
      _base=0
      for probe in /system/fonts/Roboto-Regular.ttf /system/fonts/NotoSansCJK-Regular.ttc /system/fonts/MiSansVF.ttf; do
        [ -s "$probe" ] || continue
        head -c 4 "$probe" >/dev/null 2>&1 && _base=$((_base + 1))
      done
      _cnt=$(ls /system/fonts/*.ttf 2>/dev/null | wc -l | tr -d ' ')
      _emoji=$(stat -c%s /system/fonts/NotoColorEmoji.ttf 2>/dev/null)
      log "overlay probe: base=$_base ttf=$_cnt emoji=$_emoji"
      if [ "$_base" -ge 1 ] && [ "${_cnt:-0}" -ge 5 ] && [ "$_emoji" = "$SRC_SZ" ]; then
        # 只有"保留挂载"这一种情况才落 tried，交给 service.sh 写 confirmed
        : > "$STATE/overlay_tried"
        rm -f "$STATE/overlay_confirmed"
        log "overlay kept (waiting for boot_completed to confirm)"
      else
        umount -l /system/fonts 2>/dev/null
        rm -f "$STATE/overlay_tried"
        log "overlay probe failed -> umount -l, emoji now $(stat -c%s /system/fonts/NotoColorEmoji.ttf 2>/dev/null)"
      fi
    else
      log "overlay mount FAILED"
      rm -f "$STATE/overlay_tried"
    fi
  fi
fi

# ── 5. 结果核对 ──────────────────────────────────────────────────────────────
for f in /system/fonts/*[Ee]moji*.ttf; do
  [ -e "$f" ] || continue
  log "live: $(basename "$f") = $(stat -c%s "$f" 2>/dev/null) bytes"
done

log "post-fs-data done"
exit 0
