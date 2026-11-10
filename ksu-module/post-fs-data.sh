#!/system/bin/sh
# 开机早期（/data 已挂载、zygote 未起）执行：
#   1. 读 WebUI 写入的开关（/data/adb/chiron_apple_emoji/settings.conf）
#   2. 清掉会抢优先级的 /data/fonts（GMS 下发）与主题字体目录里的 emoji
#   3. 修 SELinux 上下文，否则 system_server 读不到模块目录里的字体
#   4. bind mount 把 Apple emoji 顶到系统每一个 emoji 位点
#   5. 正文 Apple 字体 / font_fallback.xml（默认关闭）按需 bind
#   6. 全量写日志，便于下次定位
#
# 为什么还要 bind：KSU 的 overlay 在部分 ROM 上实测不生效（6.3–6.5 的教训），
# bind 是内核行为，不依赖挂载实现。

MODDIR=${0%/*}
STATE=/data/adb/chiron_apple_emoji
LOG=$STATE/post-fs.log
SYS_FONTS=/system/fonts

mkdir -p "$STATE"
: > "$LOG"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG"; }

# ── 0. 开关 ─────────────────────────────────────────────────────────────────
# EMOJI=1  挂 Apple emoji        EMOJI=0 用系统原厂 emoji
# BODY=1   换正文 Apple 字体     BODY=0  正文保持系统原样（6.7 默认）
CONF=$STATE/settings.conf
EMOJI_ON=1
BODY_ON=0
[ -f "$CONF" ] && . "$CONF" 2>/dev/null
case "$EMOJI_ON" in 0|1) ;; *) EMOJI_ON=1 ;; esac
case "$BODY_ON"  in 0|1) ;; *) BODY_ON=0  ;; esac

EMOJI_SRC="$MODDIR/system/fonts/NotoColorEmoji.ttf"
FB_SRC="$MODDIR/files/font_fallback.xml"

BODY_SRC=""
for f in "$MODDIR"/files/Roboto* "$MODDIR"/system/fonts/Roboto*; do
    [ -f "$f" ] || continue
    BODY_SRC="$f"
    break
done

log "post-fs-data start (mod=$MODDIR)"
log "settings: EMOJI=$EMOJI_ON BODY=$BODY_ON (conf=$CONF)"
[ -f "$EMOJI_SRC" ] && log "emoji src: $(stat -c%s "$EMOJI_SRC" 2>/dev/null) bytes" \
                    || log "emoji src: MISSING"
[ -n "$BODY_SRC" ] && log "body  src: $(basename "$BODY_SRC") $(stat -c%s "$BODY_SRC" 2>/dev/null) bytes"
[ -f "$FB_SRC" ] && log "fallback src: $(stat -c%s "$FB_SRC" 2>/dev/null) bytes"

# ── 1. GMS 可更新字体 ───────────────────────────────────────────────────────
if [ -d /data/fonts ]; then
    rm -rf /data/fonts
    log "removed /data/fonts"
else
    log "/data/fonts absent"
fi

# ── 2. 主题引擎字体目录 ──────────────────────────────────────────────────────
THEME_FONTS=/data/system/theme/fonts
if [ "$EMOJI_ON" = "1" ] && [ -f "$EMOJI_SRC" ]; then
    EMOJI_SZ=$(stat -c%s "$EMOJI_SRC" 2>/dev/null)
    if [ -d "$THEME_FONTS" ]; then
        n=0
        for f in "$THEME_FONTS"/*[Ee]moji*.ttf; do
            [ -e "$f" ] || continue
            CUR=$(stat -c%s "$f" 2>/dev/null)
            [ "$CUR" = "$EMOJI_SZ" ] && continue
            cp -f "$EMOJI_SRC" "$f" 2>/dev/null && {
                chmod 0644 "$f" 2>/dev/null
                chown 1000:1000 "$f" 2>/dev/null
                chcon u:object_r:system_file:s0 "$f" 2>/dev/null
                log "theme: replaced $(basename "$f") ($CUR -> $EMOJI_SZ)"
                n=$((n + 1))
            }
        done
        [ "$n" -eq 0 ] && log "theme: no emoji font to replace"
    else
        log "theme dir absent"
    fi
else
    log "theme: skipped (EMOJI=$EMOJI_ON)"
fi

# ── 3. SELinux 上下文 ────────────────────────────────────────────────────────
# 模块目录里的文件默认是 magisk_file / ksu_file 标签，system_server 没读权限，
# bind 过去也会加载失败。必须改成系统字体标签。
USE_BODY=0
[ "$BODY_ON" = "1" ] && [ -n "$BODY_SRC" ] && [ -f "$BODY_SRC" ] && USE_BODY=1
[ "$BODY_ON" = "1" ] && [ ! -f "$FB_SRC" ] && log "warn: BODY=1 but files/font_fallback.xml missing"

for f in "$EMOJI_SRC" "$BODY_SRC" "$FB_SRC"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if chcon u:object_r:system_file:s0 "$f" 2>/dev/null; then
        log "chcon ok: $(basename "$f")"
    elif restorecon "$f" 2>/dev/null; then
        log "restorecon ok: $(basename "$f")"
    else
        log "chcon failed: $(basename "$f") (will try anyway)"
    fi
done

# ── 4. bind mount emoji 到每个位点 ───────────────────────────────────────────
# 不同 ROM 的 emoji 由不同文件名分担（NotoColorEmoji / Legacy / Flags / MiSansEmoji），
# 全部顶掉，否则会出现"人脸变了但国旗还是安卓"的半吊子状态。
bound=0
if [ "$EMOJI_ON" = "1" ] && [ -f "$EMOJI_SRC" ]; then
    EMOJI_SZ=$(stat -c%s "$EMOJI_SRC" 2>/dev/null)
    for T in "$SYS_FONTS"/*[Ee]moji*.ttf /product/fonts/*[Ee]moji*.ttf \
             /system_ext/fonts/*[Ee]moji*.ttf; do
        [ -e "$T" ] || continue
        CUR=$(stat -c%s "$T" 2>/dev/null)
        if [ "$CUR" = "$EMOJI_SZ" ]; then
            log "skip (already ours): $T"
            continue
        fi
        if mount --bind "$EMOJI_SRC" "$T" 2>>"$LOG" || mount -o bind "$EMOJI_SRC" "$T" 2>>"$LOG"; then
            log "bind OK: $T  $CUR -> $(stat -c%s "$T" 2>/dev/null)"
            bound=$((bound + 1))
        else
            log "bind FAILED: $T"
        fi
    done
    log "emoji bind summary: $bound mounted"
else
    log "emoji bind skipped (EMOJI=$EMOJI_ON)"
fi

# ── 4b. 正文字体 / 字体配置（默认关闭，WebUI 打开后才挂）──────────────────────
if [ "$EMOJI_ON" = "1" ] && [ "$bound" -eq 0 ]; then
    log "no emoji bind happened"
fi

if [ "$USE_BODY" = "1" ]; then
    A=$(stat -c%s "$BODY_SRC" 2>/dev/null)
    BT="$SYS_FONTS/$(basename "$BODY_SRC")"
    if [ -f "$BT" ]; then
        B=$(stat -c%s "$BT" 2>/dev/null)
        if [ "$A" = "$B" ]; then
            log "body already ours: $(basename "$BT")"
        elif mount --bind "$BODY_SRC" "$BT" 2>>"$LOG"; then
            log "body bind OK: $(basename "$BT")  $B -> $(stat -c%s "$BT" 2>/dev/null)"
        else
            log "body bind FAILED: $(basename "$BT")"
        fi
    else
        log "body target missing: $BT"
    fi
else
    log "body bind skipped (BODY=$BODY_ON)"
fi

if [ "$BODY_ON" = "1" ] && [ -f "$FB_SRC" ]; then
    FSZ=$(stat -c%s "$FB_SRC" 2>/dev/null)
    for T in /system/etc/font_fallback.xml /system_ext/etc/font_fallback.xml \
             /product/etc/font_fallback.xml; do
        [ -f "$T" ] || continue
        if [ "$(stat -c%s "$T" 2>/dev/null)" = "$FSZ" ]; then
            log "fallback already ours: $T"
        elif mount --bind "$FB_SRC" "$T" 2>>"$LOG"; then
            log "fallback bind OK: $T"
        else
            log "fallback bind FAILED: $T"
        fi
        break
    done
elif [ "$BODY_ON" = "1" ]; then
    log "fallback bind skipped (no files/font_fallback.xml)"
fi

# ── 4c. bind 全部失败时，退一步用 overlayfs 覆盖整个 /system/fonts ────────────
if [ "$EMOJI_ON" = "1" ] && [ "$bound" -eq 0 ] && [ -f "$EMOJI_SRC" ] && \
   [ "$(stat -c%s "$SYS_FONTS/NotoColorEmoji.ttf" 2>/dev/null)" != "$(stat -c%s "$EMOJI_SRC" 2>/dev/null)" ]; then
    log "all bind failed -> trying overlayfs"
    UPPER=$STATE/ovl_upper
    WORK=$STATE/ovl_work
    rm -rf "$WORK"
    mkdir -p "$UPPER" "$WORK"
    cp -f "$EMOJI_SRC" "$UPPER/NotoColorEmoji.ttf" 2>/dev/null || log "copy to upper failed"
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
if [ "$EMOJI_ON" = "1" ] && [ -f "$EMOJI_SRC" ]; then
    EMOJI_SZ=$(stat -c%s "$EMOJI_SRC" 2>/dev/null)
    OURS=0
    TOTAL=0
    for f in "$SYS_FONTS"/*[Ee]moji*.ttf; do
        [ -e "$f" ] || continue
        TOTAL=$((TOTAL + 1))
        SZ=$(stat -c%s "$f" 2>/dev/null)
        [ "$SZ" = "$EMOJI_SZ" ] && OURS=$((OURS + 1))
        log "live: $(basename "$f") = $SZ bytes"
    done
    log "result: $OURS/$TOTAL emoji 位点已接管"

    if [ "$TOTAL" -gt 0 ] && [ "$OURS" -eq "$TOTAL" ]; then
        log "VERDICT OK  Apple emoji 已生效"
    elif [ "$OURS" -gt 0 ]; then
        log "VERDICT PARTIAL  部分位点仍是系统原版，见上面的 bind FAILED"
    else
        log "VERDICT FAIL  一个位点都没接管，请把本文件发给开发者"
    fi
else
    log "VERDICT SKIP  emoji 开关关闭（系统原厂 emoji）"
fi

log "post-fs-data done"

# 兼容旧版说明里的路径，方便直接 cat 一句话看结论
{
    echo "=== $(date) chiron_apple_emoji ==="
    echo
    cat "$LOG"
} > /data/local/tmp/chiron_font.log 2>/dev/null
chmod 0644 /data/local/tmp/chiron_font.log 2>/dev/null

exit 0
