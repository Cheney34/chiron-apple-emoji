#!/system/bin/sh
# 安装阶段（在设备上真实 shell 里执行）：把 Apple emoji 字体铺到
# 系统实际会读取的每一个文件名 / 每一个目录上。
#
# 只覆盖 /system/fonts/NotoColorEmoji.ttf 是不够的 ——
# 不同 OEM（小米、三星、OPPO…）的 fonts.xml 里 emoji 的文件名与所在分区都不同，
# 漏掉任何一个，系统就继续用它自己那份，表现就是"装了跟没装一样"。

# 兼容不同安装器（KernelSU 自带这些函数；Magisk 由 util_functions.sh 提供；
# APatch / 某些 Recovery 可能没有，这里补一份最小实现）
if ! type ui_print >/dev/null 2>&1; then ui_print() { echo "$1"; }; fi
if ! type abort    >/dev/null 2>&1; then abort()    { echo "$1"; exit 1; }; fi
if ! type set_perm >/dev/null 2>&1; then
  set_perm() { chown "$2:$3" "$1" 2>/dev/null; chmod "$4" "$1" 2>/dev/null; }
fi
if ! type set_perm_recursive >/dev/null 2>&1; then
  set_perm_recursive() {
    find "$1" -type d -exec chmod "$3" {} + 2>/dev/null
    find "$1" -type f -exec chmod "$4" {} + 2>/dev/null
  }
fi

ui_print " "
ui_print "****************************************"
ui_print "  Apple Color Emoji · v5.0"
ui_print "  Unicode 16 / iOS 18.4 全量"
ui_print "****************************************"
ui_print " "

SRC="$MODPATH/system/fonts/NotoColorEmoji.ttf"
[ -f "$SRC" ] || abort "! 安装包缺少字体文件，请重新下载"

SZ=$(stat -c%s "$SRC" 2>/dev/null)
ui_print "- 字体包 $((${SZ:-0} / 1048576)) MB"

# ── 系统真实路径 → 模块内挂载路径 ─────────────────────────────────────────────
# KernelSU / Magisk 只识别模块内 system/ product/ system_ext/ 这些顶层目录，
# 因此 /product/fonts 必须放成 $MODPATH/product/fonts，不能塞进 system/。
map_path() {
  case "$1" in
    /system/system/*)   echo "$MODPATH/system/${1#/system/system/}" ;;
    /system/*)          echo "$MODPATH$1" ;;
    /product/*)         echo "$MODPATH/product/${1#/product/}" ;;
    /system_ext/*)      echo "$MODPATH/system_ext/${1#/system_ext/}" ;;
    /vendor/*)          echo "$MODPATH/vendor/${1#/vendor/}" ;;
    *)                  echo "" ;;
  esac
}

# 同一分区内用硬链接，避免 111 MB × N 份把 /data 撑爆
link_in() {
  _dst="$1"
  [ -f "$_dst" ] && return 0
  mkdir -p "$(dirname "$_dst")" 2>/dev/null
  ln "$SRC" "$_dst" 2>/dev/null || cp -f "$SRC" "$_dst" 2>/dev/null
}

# ── 1. 从 fonts.xml 解析出系统真正引用的 emoji 字体名 ─────────────────────────
ui_print "- 解析系统字体配置…"
NAMES=""

for XML in /system/etc/fonts.xml /system/etc/font_fallback.xml \
           /product/etc/fonts.xml /product/etc/font_fallback.xml \
           /system_ext/etc/fonts.xml; do
  [ -f "$XML" ] || continue
  # und-Zsye 是 emoji 家族的固定 lang 标记；同时兜住任何文件名带 emoji 的引用
  _n=$(awk '
    /und-Zsye|<family[^>]*emoji/ { in_emoji = 1 }
    in_emoji && /<\/family>/      { in_emoji = 0 }
    {
      line = $0
      while (match(line, /[A-Za-z0-9._-]+\.ttf/)) {
        name = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        if (in_emoji == 1 || name ~ /[Ee]moji/) print name
      }
    }
  ' "$XML" 2>/dev/null | sort -u)
  [ -n "$_n" ] && NAMES="$NAMES
$_n"
done

NAMES=$(printf '%s\n' "$NAMES" | sed '/^$/d' | sort -u)
if [ -n "$NAMES" ]; then
  ui_print "  系统引用的 emoji 字体："
  printf '%s\n' "$NAMES" | while IFS= read -r n; do ui_print "    · $n"; done
else
  ui_print "  未解析到（将使用通用文件名兜底）"
fi

# ── 2. 兜底名单：常见 OEM 文件名 ──────────────────────────────────────────────
FALLBACK="NotoColorEmoji.ttf
MiSansEmoji.ttf
NotoColorEmojiLegacy.ttf"

LIST=$(printf '%s\n%s\n' "$NAMES" "$FALLBACK" | sed '/^$/d' | sort -u)

# ── 3. 铺文件 ────────────────────────────────────────────────────────────────
ui_print "- 建立字体覆盖…"

printf '%s\n' "$LIST" | while IFS= read -r NAME; do
  [ -n "$NAME" ] || continue
  BASENAME="${NAME##*/}"

  # 先看系统上是否真的存在这个文件，找到就用它的真实目录
  FOUND=""
  case "$NAME" in
    /*) [ -f "$NAME" ] && FOUND="$NAME" ;;
  esac
  if [ -z "$FOUND" ]; then
    for D in /system/fonts /system/system/fonts /product/fonts \
             /system/product/fonts /system_ext/fonts /vendor/fonts; do
      if [ -f "$D/$BASENAME" ]; then FOUND="$D/$BASENAME"; break; fi
    done
  fi

  if [ -n "$FOUND" ]; then
    DST=$(map_path "$FOUND")
    if [ -n "$DST" ]; then
      link_in "$DST"
      FSZ=$(stat -c%s "$FOUND" 2>/dev/null)
      ui_print "  ✓ $FOUND ($((${FSZ:-0} / 1024)) KB) → 已接管"
    fi
  fi

  # 无论系统上有没有，都在默认位补一份，防止系统临时按名字查找
  link_in "$MODPATH/system/fonts/$BASENAME"
done

# 主文件本体确保存在
[ -f "$MODPATH/system/fonts/NotoColorEmoji.ttf" ] || cp -f "$SRC" "$MODPATH/system/fonts/NotoColorEmoji.ttf"

ui_print "- 模块内字体文件："
for f in "$MODPATH"/system/fonts/*.ttf; do
  [ -f "$f" ] && ui_print "    $(basename "$f") $(($(stat -c%s "$f") / 1024)) KB"
done

# ── 4. 清掉会抢优先级的上层字体 ───────────────────────────────────────────────
# 安装时先清一遍，开机后 post-fs-data / service 还会再清（GMS 可能重新下发）
if [ -d /data/fonts ]; then
  rm -rf /data/fonts && ui_print "- 已清除 /data/fonts（GMS 下发的字体包）"
fi

if [ -d /data/system/theme/fonts ]; then
  _hit=0
  for f in /data/system/theme/fonts/*[Ee]moji*.ttf; do
    [ -e "$f" ] || continue
    rm -f "$f" && _hit=$((_hit + 1))
  done
  [ "$_hit" -gt 0 ] && ui_print "- 已清除主题字体目录中的 $_hit 个 emoji 字体"
fi

# ── 5. 权限 ──────────────────────────────────────────────────────────────────
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/action.sh"       0 0 0755
set_perm "$MODPATH/scripts/diag.sh" 0 0 0755

ui_print " "
ui_print "- 安装完成，重启后生效"
ui_print "- 重启后如仍无变化，进模块详情点「执行」按钮跑一次诊断"
ui_print " "
