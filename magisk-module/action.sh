#!/system/bin/sh
# KernelSU / Magisk 模块详情页的「执行」按钮。
# 现场做一次 bind mount + 清缓存 + 诊断，不用重启就能知道成不成。

MODDIR=${0%/*}
SRC=$MODDIR/system/fonts/NotoColorEmoji.ttf
SRC_SZ=$(stat -c%s "$SRC" 2>/dev/null)

echo ""
echo "===== Apple Color Emoji · 一键修复 ====="
echo ""

# 0. SELinux 上下文
if chcon u:object_r:system_file:s0 "$SRC" 2>/dev/null; then
  echo "OK  SELinux 上下文已设为 system_file"
else
  echo "--  chcon 失败（继续尝试）"
fi

# 1. GMS 可更新字体（挪进备份，不删）
if [ -d /data/fonts ]; then
  BK=/data/adb/chiron_apple_emoji/backup/gms-$(date +%Y%m%d-%H%M%S)
  if mkdir -p "$BK" 2>/dev/null && mv /data/fonts "$BK/data-fonts" 2>/dev/null; then
    echo "dir|/data/fonts|$BK/data-fonts" >> /data/adb/chiron_apple_emoji/backup/journal.txt
    echo "OK  /data/fonts 已移入备份（GMS 字体包）: $BK"
  else
    echo "!!  /data/fonts 无法移走，保持原样"
  fi
else
  echo "--  /data/fonts 不存在"
fi

# 2. 主题字体目录里的 emoji（覆盖前先备份一次，保留用户原始那份）
n=0
if [ -d /data/system/theme/fonts ]; then
  BKT=/data/adb/chiron_apple_emoji/backup/theme
  mkdir -p "$BKT" 2>/dev/null
  for f in /data/system/theme/fonts/*[Ee]moji*.ttf; do
    [ -e "$f" ] || continue
    [ "$(stat -c%s "$f" 2>/dev/null)" = "$SRC_SZ" ] && continue
    _nm=$(basename "$f")
    if [ ! -f "$BKT/$_nm" ]; then
      cp -p "$f" "$BKT/$_nm" 2>/dev/null || { echo "!!  备份失败，跳过 $_nm"; continue; }
      echo "file|$f|$BKT/$_nm" >> /data/adb/chiron_apple_emoji/backup/journal.txt
    fi
    cp -f "$SRC" "$f" 2>/dev/null && n=$((n + 1))
  done
fi
echo "OK  主题字体目录替换 $n 个 emoji 字体"

# 3. bind mount
echo ""
echo "--- 挂载 /system/fonts 下的 emoji 字体 ---"
bound=0
for T in /system/fonts/*[Ee]moji*.ttf; do
  [ -e "$T" ] || continue
  CUR=$(stat -c%s "$T" 2>/dev/null)
  if [ "$CUR" = "$SRC_SZ" ]; then
    echo "  跳过（已是我们的）: $(basename "$T")"
    continue
  fi
  if mount --bind "$SRC" "$T" 2>/dev/null || mount -o bind "$SRC" "$T" 2>/dev/null; then
    echo "  成功: $(basename "$T")  $CUR -> $(stat -c%s "$T" 2>/dev/null)"
    bound=$((bound + 1))
  else
    echo "  失败: $(basename "$T")  (当前 $CUR 字节)"
  fi
done
echo "  合计 $bound 个位点已挂载"

# 4. 字形缓存
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
