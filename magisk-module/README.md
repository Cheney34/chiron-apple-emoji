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
安装时   customize.sh     → 复制字体、建立 /system/fonts 下的软链
开机早期 post-fs-data.sh  → mount --bind 覆盖系统字体，失败则走 overlayfs
开机后   service.sh       → 清理 /data/fonts 抢占（可更新系统字体），禁用 GMS FontsProvider
出问题   action.sh        → 一键还原 / 诊断
```

`scripts/diag.sh` 会把 `/system/fonts` 里所有 emoji 字体的实际大小、是否被接管、
`/data/fonts` 是否存在，写到 `/data/local/tmp/emoji_diag.txt`。

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

## 已知问题（待修）

审计报告里有四条，按严重程度排：

| 问题 | 位置 | 后果 |
|---|---|---|
| `rm -f /data/system/theme/fonts/*emoji*.ttf` | `customize.sh` | 删掉用户主题里的 emoji，**无备份** |
| `pm disable` GMS FontsProvider | `service.sh` | **不可逆**，且没有 `uninstall.sh`，卸载后 Google 字体下载功能永久消失 |
| overlayfs 挂 `/system/fonts` | `post-fs-data.sh` | upperdir 的 SELinux 标签是 `magisk_file`，回滚探测只看文件非空、不看能否加载 → 系统 UI 起不来的风险 |
| `ln` 失败退 `cp` | `customize.sh` | 跨分区时最多产生 3×180 MB 拷贝，无检查 |

另外 `update-binary` 硬编码 `. /data/adb/magisk/util_functions.sh`，APatch 的脚本在
`/data/adb/ap/`，`install_module` 未定义时会 `exit 0` —— 装了个寂寞。

完整分析见 [../docs/审计报告.md](../docs/审计报告.md)。
