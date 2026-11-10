#!/system/bin/sh
# WebUI 用的开关脚本：把设置写进 settings.conf，必要时搬动模块内的字体文件。
#   set-state.sh emoji on|off      on = Apple 17.0，off = 系统原厂 AOSP
#   set-state.sh body  on|off      on = 正文也换成 Apple 字体（默认 off）
#   set-state.sh show              打印当前状态
#
# 为什么 emoji 要搬文件：KSU 的 overlay 是把模块的 system/fonts 整个盖到 /system 上，
# 只要文件还在 system/fonts 里，关掉 bind 也没用 —— 必须把文件挪出 overlay 目录。
# 搬走的是模块自己的副本，随时能搬回来；系统原厂那份从来不动。

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
STATE=/data/adb/chiron_apple_emoji
CONF=$STATE/settings.conf

mkdir -p "$STATE" 2>/dev/null
[ -f "$CONF" ] || printf 'EMOJI=1\nBODY=0\n' > "$CONF"
. "$CONF" 2>/dev/null
EMOJI=${EMOJI:-1}
BODY=${BODY:-0}

KEY=$1
VAL=$2

case "$KEY" in
  emoji)
    if [ "$VAL" = "off" ]; then
      mkdir -p "$MODDIR/files/off" 2>/dev/null
      n=0
      for f in "$MODDIR"/system/fonts/*[Ee]moji*.ttf; do
        [ -e "$f" ] || continue
        mv -f "$f" "$MODDIR/files/off/" 2>/dev/null && n=$((n + 1))
      done
      EMOJI=0
      echo "emoji -> off（移出 $n 个字体文件）"
    else
      mkdir -p "$MODDIR/system/fonts" 2>/dev/null
      n=0
      for f in "$MODDIR"/files/off/*; do
        [ -e "$f" ] || continue
        mv -f "$f" "$MODDIR/system/fonts/" 2>/dev/null && n=$((n + 1))
      done
      EMOJI=1
      echo "emoji -> on（放回 $n 个字体文件）"
    fi
    ;;
  body)
    if [ "$VAL" = "off" ]; then
      BODY=0 ; echo "body -> off"
    else
      BODY=1 ; echo "body -> on"
    fi
    ;;
  show|"")
    echo "EMOJI=$EMOJI BODY=$BODY"
    exit 0
    ;;
  *)
    echo "usage: set-state.sh emoji|body on|off"
    exit 1
    ;;
esac

printf 'EMOJI=%s\nBODY=%s\n' "$EMOJI" "$BODY" > "$CONF"
echo "已写入 $CONF"
cat "$CONF"
echo "重启后完全生效"
