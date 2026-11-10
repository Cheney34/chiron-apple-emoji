# Chiron × Apple Emoji · 类原生 KSU 字体模块

给类原生 AOSP（Infinity X / Android 17）用的字体模块。6.7 起主职是 emoji，正文可选：

| 内容 | 换成什么 | 默认 |
|---|---|---|
| Emoji | Apple 彩色 emoji（Emoji 17.0 / iOS 26 字形，RGBA 真彩 32/45/60/82/128 五档位图） | 开 |
| 正文字体 | Chiron GoRound TC + Merriweather（静态化，`wght=400`） | 关（WebUI 可开） |

- 模块 id：`chiron_apple_emoji`（沿用 5.0 / 6.2 这条线，KSU 里是**升级**，不会多出一条）
- 版本：`v6.7`（versionCode 13）
- 适用：KernelSU / Magisk / APatch，Android 14+（WebUI 需要 KernelSU）

## 6.7：三件事

**1. 输入框光标消失 → 正文字体默认不换**

6.5.1 起模块把 66 MB 的 `Chiron GoRound TC VF` 塞进了 `system/fonts/Roboto-Regular.ttf`。
那是可变字体，`OS/2.usWeightClass=330`、`fvar` 默认实例也是 330，而系统字体配置按 **400** 找它；
再加上 41 MB 的 `gvar` 要在渲染前实例化 5 万个字形。表现就是微信、抖音输入框里**打字没有光标**，
以及公众号页的日期/天气不刷新（WebView 首屏排版把那段文本整段跳过）。

6.7 把正文字体挪到 `files/`，**默认不挂载**，回到 5.0 的行为；需要正文字体时在 WebUI 里单独打开。
同时字体本身做了静态化：删 `fvar`/`gvar`/`STAT`，`usWeightClass` 改成 400，69 MB → 28 MB。

**2. 组合 emoji 被拆开 / 显示成空白**

`🙂‍↕️ 🙂‍↔️ 👩‍⚕️ ➡️` 这类是 ZWJ 组合（多个码位 + `U+200D` 拼成一个表情）。
把它们拆开看，是「彩脸 + 黑白箭头」；如果表情面板把 `U+FE0F` 去掉，还会剩一段空白。

原因不在 emoji 字体（那份 4006 字形、3730 条连字、位图齐全），而在**正文字体抢了组件码位**：
Chiron 是 CJK 字体，把 `U+2194 ↔`、`U+2195 ↕`、`U+2640 ♀`、`U+2642 ♂`、`U+27A1 ➡`
当成全角符号收进了 cmap（宽度 1000/1000 em）。系统逐字符挑字体时，
这几个字符落到正文字体上，run 一断，连字就组不起来了。

6.7 把**这 5 个码位从正文字体的 cmap 里摘掉**（只动映射，`glyf`/`hmtx`/`GSUB`/`GPOS` 一字节没动），
它们就只剩下 emoji 字体一个来源，整个组合能落在同一个字体里，连字生效。
另外 95 个组件码位（`U+20E3` 键帽、`U+26A7`、区域指示符 `U+1F1E6..`、肤色修饰符 `U+1F3FB..`）本来就不在正文字体里，无需处理。

**3. WebUI**

模块详情页多了一个入口，能看状态、切表情包、开关正文字体、跑诊断、导出日志、重启。
见下面「WebUI」一节。

## 6.6：找到「还是安卓风格」的真凶

6.3 起为了压体积，emoji 字体只做了 **32/45/60 三个档位**（38/53/70 px）。
CBDT/CBLC 是**定点位图**字体 —— 系统按实际渲染像素挑 strike。

大字号时（emoji 键盘预览、表情详情、通知、微信大表情）系统请求 96 px / 150 px，
字体里没有对应档位，FreeType 返回 size 不匹配，Minikin 判定「这个字体画不出来」，
于是**整段回退到系统自带的 NotoColorEmoji**——也就是安卓那张扁平脸。

所以症状很迷惑：小字号看着像 iOS，一放大就变安卓；有的 App 对有的 App 不对。

5.0 那版用的是 **32/45/60/82/128 五档**（38/53/70/96/150 px），从不缺档。
6.6 恢复五档，字体体积回到 ~190 MB，这是正常的。

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

KSU Manager → 模块 → 从本地安装 → 选 `Chiron_KSU_Font_A17_v6.7.zip` → 重启。

安装时会：

1. 扫 `/data/adb/modules`，把仍在改同一批字体的模块点名打出来（只报告，不动别人的模块）；
2. 如果本模块目录下有 `disable` 标记，自动清掉（否则装了也不挂载）；
3. 探测系统 Roboto 的真实文件名，把模块内正文字体改成同名（放在 `files/`，默认不挂）；
4. 在 `font_fallback.xml` 的 zh-Hans / zh-Hant 家族首位插入我们的字体（只在打开正文字体时挂）；
5. 按 `fonts.xml` 解析出的 emoji 文件名逐个铺，并清掉 `/data/fonts` 与主题目录里的 emoji；
6. 写默认开关 `EMOJI=1 BODY=0`（已存在就保留你上次的选择）。

## WebUI

模块详情页的 WebUI（需要 KernelSU；Magisk 没有这个接口）：

| 区块 | 能做什么 |
|---|---|
| 状态 | emoji 接管了几个位点、正文字体有没有换、当前开关 |
| 表情包 | `Apple 17.0` ↔ `系统原厂`。选原厂会把模块内的 emoji 字体移到 `files/off/`，让 overlay 里也没有它 |
| 正文字体 | `不换（默认）` ↔ `换成 Apple 字体`。打开会提示光标风险 |
| 操作 | 立即重挂载 / 运行诊断 / 导出日志到 `/sdcard/Download/` / 重启 |

开关写进 `/data/adb/chiron_apple_emoji/settings.conf`，重启后由 `post-fs-data.sh` 读取。
命令行等价物：

```bash
su -c 'sh /data/adb/modules/chiron_apple_emoji/scripts/set-state.sh show'
su -c 'sh /data/adb/modules/chiron_apple_emoji/scripts/set-state.sh body off'
su -c 'sh /data/adb/modules/chiron_apple_emoji/scripts/set-state.sh emoji off'
```

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
system/fonts/NotoColorEmoji.ttf  190 MB   Apple emoji（Emoji 17.0，CBDT 32/45/60/82/128 五档）
files/Roboto-Regular.ttf          28 MB   Chiron GoRound TC + Merriweather（静态 wght=400，默认不挂）
files/font_fallback.xml                  安装期从系统原文件生成（只在中文家族前插 9 行）
webroot/index.html                       WebUI（KernelSU 模块详情页打开）
system.prop                              禁用 GMS 可更新字体
customize.sh                             安装期：铺文件名 / 改配置 / 清上层字体 / 写默认开关
post-fs-data.sh                          开机早期：读开关 + chcon + bind mount + overlayfs 兜底
service.sh                               开机完成：清缓存 / 关 FontsProvider / 补挂
action.sh                                模块详情页「执行」按钮（按当前开关重挂 + 诊断）
scripts/diag.sh                          诊断
scripts/set-state.sh                     WebUI 的开关实现（emoji on/off、body on/off）
uninstall.sh                             清理状态目录
```

## 更新日志

- **v6.7** 正文字体改为默认不挂载（修微信/抖音输入框光标消失）+ 静态化（`wght=400`，删 `fvar`/`gvar`）；
  正文字体 cmap 摘掉 `U+2194/2195/2640/2642/27A1`，修 `🙂‍↕️ 🙂‍↔️ 👩‍⚕️ ➡️` 被拆成「彩脸 + 黑白箭头」；
  新增 WebUI（表情包切换 / 正文开关 / 诊断 / 日志导出）。
- **v6.6** emoji 位图从 3 档恢复到 5 档（38/53/70/96/150 px），修掉「大字号掉回安卓字形」；
- **v6.5.2** 恢复 5.0 的四道保险（bind mount / 铺满文件名 / 禁 GMS 下发 / 清缓存），修掉「emoji 变回安卓风格」；
  安装时自动清掉自身的 `disable` 标记；正文字体与 `font_fallback.xml` 在 overlay 没盖住时也一并 bind。
  字体内容与 6.5 / 6.5.1 完全一致。
- **v6.5.1** 模块 id 回到 `chiron_apple_emoji`，安装时点名冲突模块。
- **v6.5** 表情库升到 Emoji 17.0（iOS 26 字形）。
