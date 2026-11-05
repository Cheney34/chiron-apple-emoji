#!/system/bin/sh
# 开机早期（/data 已挂载、zygote 未起）执行，四件事：
#   1. 清掉会抢优先级的 /data/fonts（GMS 下发）与主题字体目录里的 emoji
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

# ── 1. GMS 可更新字体 ────────────────────────────────────────────────────────
if [ -d /data/fonts ]; then
  rm -rf /data/fonts
  log "removed /data/fonts"
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

# ── 4b. bind 全部失败时，退一步用 overlayfs 覆盖整个 /system/fonts ────────────
# 只替换一个文件不够用（某些 ROM 对 /system 单个文件的 bind 有限制），
# 但整目录 overlay 风险更高：挂完立刻验证常规字体还能读，读不到就立刻回滚，
# 否则系统 UI 会因为拿不到字体而起不来。
if [ "$bound" -eq 0 ]; then
  log "all bind failed -> trying overlayfs"
  UPPER=$STATE/ovl_upper
  WORK=$STATE/ovl_work
  rm -rf "$WORK"
  mkdir -p "$UPPER" "$WORK"
  cp -f "$SRC" "$UPPER/NotoColorEmoji.ttf" 2>/dev/null || log "copy to upper failed"
  chcon u:object_r:system_file:s0 "$UPPER/NotoColorEmoji.ttf" 2>/dev/null
  chmod 0644 "$UPPER/NotoColorEmoji.ttf" 2>/dev/null

  if mount -t overlay overlay -o "lowerdir=/system/fonts,upperdir=$UPPER,workdir=$WORK" /system/fonts 2>>"$LOG"; then
    OKFONT=0
    for probe in /system/fonts/Roboto-Regular.ttf /system/fonts/NotoSansCJK-Regular.ttc /system/fonts/MiSansVF.ttf; do
      [ -s "$probe" ] && OKFONT=1 && break
    done
    if [ "$OKFONT" -eq 1 ]; then
      log "overlay OK: NotoColorEmoji.ttf=$(stat -c%s /system/fonts/NotoColorEmoji.ttf 2>/dev/null)"
    else
      umount -l /system/fonts 2>/dev/null
      log "overlay mounted but base fonts unreadable -> reverted"
    fi
  else
    log "overlay mount FAILED"
  fi
fi

# ── 5. 结果核对 ──────────────────────────────────────────────────────────────
for f in /system/fonts/*[Ee]moji*.ttf; do
  [ -e "$f" ] || continue
  log "live: $(basename "$f") = $(stat -c%s "$f" 2>/dev/null) bytes"
done

log "post-fs-data done"
exit 0
