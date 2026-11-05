# magisk-module

把 emoji 字体挂进 `/system/fonts` 的 Magisk / KernelSU / APatch 模块。

## 打包

```bash
cd magisk-module
mkdir -p system/fonts
cp /path/to/NotoColorEmoji.ttf system/fonts/
zip -r ../AppleEmoji-Chiron.zip . -x '*.git*' 'README.md'
```

> `system/fonts/NotoColorEmoji.ttf` 不在仓库里（第三方美术资源，见根目录 THIRD-PARTY.md）。
> 用 [`../emoji-font/`](../emoji-font/) 的脚本自己生成。

刷入后重启。首次安装会打印挂载结果到 `/data/adb/modules/chiron_apple_emoji/post-fs.log`。

## 执行链

```
安装时   customize.sh     → 复制字体、建立 /system/fonts 下的链接；
                            覆盖主题 emoji 前先备份到 /data/adb/chiron_apple_emoji/backup/
开机早期 post-fs-data.sh  → mount --bind 覆盖系统字体（overlay 兜底默认关闭）
开机后   service.sh       → 挪走 /data/fonts（不删）、禁用 GMS FontsProvider 并记清单
出问题   action.sh        → 一键重挂 / 诊断
卸载时   uninstall.sh     → 还原 GMS 组件、还原主题字体、卸掉 bind mount
```

`scripts/diag.sh` 会把 `/system/fonts` 里所有 emoji 字体的实际大小、是否被接管、
`/data/fonts` 是否存在，写到 `/data/local/tmp/emoji_diag.txt`。

### 改过系统什么（可还原性）

| 动作 | 落点 | 还原方式 |
|---|---|---|
| bind mount emoji 字体 | `/system/fonts/*emoji*.ttf` | 重启即清；`uninstall.sh` 也会立即 umount |
| 挪走 GMS 字体包 | `/data/fonts` → `…/backup/{install,gms}-*/data-fonts` | `uninstall.sh` 放回；只保留最近 2 份 |
| 覆盖主题 emoji | `/data/system/theme/fonts/` | 覆盖前 `cp -p` 备份，`journal.txt` 记账，`uninstall.sh` 还原 |
| `pm disable` GMS 字体组件 | 系统包状态 | 禁一项记一行到 `disabled.list`，`uninstall.sh` 逐行 `pm enable` |

备份根目录：`/data/adb/chiron_apple_emoji/backup/`。

## overlay 兜底（默认关闭）

bind mount 全部失败时，旧版会自动用 overlayfs 盖住整个 `/system/fonts`。
upperdir 里的字体 SELinux 标签是 `magisk_file`，一旦挂上又加载失败，
表现是 SystemUI 循环崩溃，而且下次开机还会再挂一次 —— 死循环。

现在改为手动开启：

```bash
su -c 'touch /data/adb/chiron_apple_emoji/enable_overlay'   # 开启，重启生效
```

并且带熔断：挂上后写入 `overlay_tried`，`service.sh` 在开机完成后写 `overlay_confirmed`；
下次开机若发现「有 tried 没 confirmed」，说明上次没熬过开机，overlay 永久停用。
排查后删掉 `overlay_tried` 可重新尝试。

探测条件（同时满足才保留挂载，否则立即 `umount -l`）：
基础字体可读 + `/system/fonts/*.ttf` 数量正常 + emoji 已是本模块那份。

## 已知问题（待修）

审计报告里的 P0 代码项已处理完，剩下这些：

| 问题 | 位置 | 状态 |
|---|---|---|
| MTZ 版 emoji 是 256 色单档、advance width 未归一化 | 字体二进制 | 待用同一源重建（`emoji-font/`） |
| 字体授权未确认 | 包内 | 已加 `NOTICE.txt`，公开发布仍需维护者确认 |
| `ln` 失败退 `cp`，跨分区时最多 3×180 MB 拷贝 | `customize.sh` | 未改，仍是空间风险 |
| 180 MB 字体 stored 未压缩 | 打包 | 未改 |

已修（v5.1）：无备份 `rm -f` 主题 emoji、`rm -rf /data/fonts`、不可逆 `pm disable`、
无 `uninstall.sh`、overlay 自动回退、`update-binary` 静默失败。

完整分析见 [../docs/审计报告.md](../docs/审计报告.md)。

## 为什么有时不生效

emoji 在 Android 上有三条通道，这个模块只处理第一条：

| 层 | 谁在用 | 换 `/system/fonts` 管得到吗 |
|---|---|---|
| L1 平台文本渲染 | 系统 UI、微信、QQ、大部分原生控件 | ✅ |
| L2 可更新系统字体（`/data/fonts`） | Android 12+ FontManager 下发 | ❌ 模块会去清理 |
| L3 App 自带渲染器 / 自带 emoji 字体 | 酷安、微博、部分 H5 容器 | ❌ 完全管不到 |

酷安、微博这类 App 自带 emoji 字体（`emoji2-bundled` 约 10 MB 打进 APK），
任何系统级替换都无效。这不是模块的问题，详见
[../docs/emoji字体通道分析.md](../docs/emoji字体通道分析.md)。

**自检三步**：

1. 把一个 emoji 粘贴到「设置 → 搜索框」。设置里是苹果、App 里是安卓 → 系统已生效，是 App 的事；
2. 跑 `bash scripts/diag.sh`，看 `[已接管]` / `[未接管]` 和 `/data/fonts`；
3. 清 App 缓存 + 强制停止再开，还不行就是 App 自带渲染。
