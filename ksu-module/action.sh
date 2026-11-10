#!/system/bin/sh
# 模块详情页的「执行」按钮：现场按当前开关重挂一次 + 打印诊断，不用重启也能看到结论。
# （字体服务会缓存旧字体，界面要完全生效仍需重启；新拉起的 App 会立刻用新字体。）

MODDIR=${0%/*}
STATE=/data/adb/chiron_apple_emoji
CONF=$STATE/settings.conf

echo ""
echo "===== Chiron x Apple Emoji 6.7 ====="
echo ""

if [ -f "$CONF" ]; then
    echo "--- 当前开关 ($CONF) ---"
    cat "$CONF"
else
    echo "--- 当前开关：未设置（emoji 开 / 正文关）---"
fi
echo ""

# 直接复用开机脚本，保证行为一致
sh "$MODDIR/post-fs-data.sh"

echo "--- post-fs-data 日志 ---"
if [ -f "$STATE/post-fs.log" ]; then
    cat "$STATE/post-fs.log"
else
    echo "（没有日志）"
fi

echo ""
echo "--- 诊断 ---"
sh "$MODDIR/scripts/diag.sh" /data/local/tmp/chiron_diag.txt
if [ -f /data/local/tmp/chiron_diag.txt ]; then
    cat /data/local/tmp/chiron_diag.txt
fi

echo ""
echo "======================================="
