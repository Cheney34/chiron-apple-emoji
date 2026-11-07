# Chiron × Apple Emoji · 类原生 KSU 字体模块

给类原生 AOSP（Infinity X / Android 17）用的字体模块。一次刷入，同时换掉三样东西：

| 内容 | 换成什么 |
|---|---|
| 中文字体 | Chiron GoRound TC |
| 西文与数字 | Merriweather（合并进同一个字体文件） |
| Emoji | Apple 彩色 emoji（Emoji 17.0 / iOS 26 字形，RGBA 真彩 32/45/60 三档位图） |

- 模块 id：`chiron_apple_emoji`（沿用 5.0 / 6.2 这条线，KSU 里是**升级**，不会多出一条）
- 版本：`v6.5.2`（versionCode 11）
- 适用：KernelSU / Magisk / APatch，Android 14+

## 为什么 6.5.2 要重做挂载

6.3 重写模块时，把 5.0 里的四道保险全删了，只剩「模块自带 `system/fonts/` 目录」这一条路。
本机（Android 17）实测 **overlay 不保证生效**：`/system/fonts/NotoColorEmoji.ttf` 仍是系统原版，
于是 emoji 能显示（系统自带 Noto 也有这些码位），但画出来是**安卓风格**，不是苹果的。

6.5.2 把 5.0 的做法整套搬回来：

| 保险 | 在哪 | 作用 |
|---|---|---|
| 禁用 GMS 字体下发 | `system.prop` | `/data/fonts` 优先级高于 `/system/fonts`，不禁止就会盖回来 |
| 铺满 emoji 文件名 | `customize.sh` | 解析 `fonts.xml` / `font_fallback.xml`，把系统真正引用的 `NotoColorEmoji` / `NotoColorEmojiLegacy` / `NotoColorEmojiFlags` / `MiSansEmoji` 全部接管 |
| bind mount | `post-fs-data.sh` | 内核行为，不依赖 KSU 的 overlay；逐个顶掉 `*Emoji*.ttf` 位点，并修 SELinux 上下文 |
| 清缓存 + 关 provider | `service.sh` | 开机后清 `/data/fonts`、主题字体目录、字形缓存，断掉重新下发的源头 |

## 安装

KSU Manager → 模块 → 从本地安装 → 选 `Chiron_KSU_Font_A17_v6.5.2.zip` → 重启。

安装时会：

1. 扫 `/data/adb/modules`，把仍在改同一批字体的模块点名打出来（只报告，不动别人的模块）；
2. 如果本模块目录下有 `disable` 标记，自动清掉（否则装了也不挂载）；
3. 探测系统 Roboto 的真实文件名，把模块内正文字体改成同名；
4. 在 `font_fallback.xml` 的 zh-Hans / zh-Hant 家族首位插入我们的字体；
5. 按 `fonts.xml` 解析出的 emoji 文件名逐个铺，并清掉 `/data/fonts` 与主题目录里的 emoji。

### 从 6.3 / 6.4 / 6.5 迁回来

1. 直接装 6.5.2；
2. 到模块列表把 `Chiron × Apple Emoji（类原生）`（id `chiron_ksu_font`）**卸载**；
3. 重启。

### 从 5.0 / 5.1 / 6.2 升级

直接装。id 没变，是升级覆盖，不会并列。

## 装了没效果怎么查

模块详情页点「**执行**」按钮：会现场 bind mount 一次、清缓存，并打印完整诊断；
诊断同时写到 `/sdcard/emoji_diag.txt`。

或者手动看日志：

```bash
su -c cat /data/adb/chiron_apple_emoji/post-fs.log
su -c cat /data/local/tmp/chiron_font.log     # 同一份内容
```

关键两行：

```
emoji src: 60277864 bytes
result: 3/3 emoji 位点已接管
VERDICT OK  Apple emoji 已生效
```

- `VERDICT OK` → 字体层已生效。若界面仍是安卓表情，是那个 App 自带图片（微信、QQ 的表情面板），与字体无关。
- `VERDICT PARTIAL` / `FAIL` → 看上面的 `bind FAILED` 行，把日志发回来。
- 完全没日志 → 模块没跑起来，检查是否被禁用（`/data/adb/modules/chiron_apple_emoji/disable`）。

## 包内文件

```
system/fonts/NotoColorEmoji.ttf   60 MB   Apple emoji（Emoji 17.0，CBDT 32/45/60 三档）
system/fonts/Roboto-Regular.ttf   69 MB   Chiron GoRound TC + Merriweather
system/etc/font_fallback.xml             安装期从系统原文件生成（只在中文家族前插 9 行）
system.prop                              禁用 GMS 可更新字体
customize.sh                             安装期：铺文件名 / 改配置 / 清上层字体
post-fs-data.sh                          开机早期：chcon + bind mount + overlayfs 兜底
service.sh                               开机完成：清缓存 / 关 FontsProvider / 补挂
action.sh                                模块详情页「执行」按钮
scripts/diag.sh                          诊断
uninstall.sh                             清理状态目录
```

## 更新日志

- **v6.5.2** 恢复 5.0 的四道保险（bind mount / 铺满文件名 / 禁 GMS 下发 / 清缓存），修掉「emoji 变回安卓风格」；
  安装时自动清掉自身的 `disable` 标记；正文字体与 `font_fallback.xml` 在 overlay 没盖住时也一并 bind。
  字体内容与 6.5 / 6.5.1 完全一致。
- **v6.5.1** 模块 id 回到 `chiron_apple_emoji`，安装时点名冲突模块。
- **v6.5** 表情库升到 Emoji 17.0（iOS 26 字形）。
