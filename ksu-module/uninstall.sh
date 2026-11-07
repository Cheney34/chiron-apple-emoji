#!/system/bin/sh
# 模块卸载：bind mount 与 magic mount 都随重启撤销，/system 自动恢复原状。
# 这里只清理运行期状态目录与日志，避免下次装上时读到旧记录。

rm -rf /data/adb/chiron_apple_emoji
rm -f /data/local/tmp/chiron_font.log
