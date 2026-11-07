# Chiron × Apple Emoji 6.5.2

表情库升到 **Emoji 17.0 / iOS 26 字形**。正文一个字没动。

Unicode 17.0 于 2025-09 定稿，苹果在 iOS 26.4 测试版里把这批图画补齐了。这一版把苹果的
正式美术全部收进字体 —— 不是第三方仿画，也不是 Google Noto 的设计。

## 6.5.2 修「装上了却还是安卓风格」

6.5 / 6.5.1 只靠模块自带的 `system/fonts/` 目录（overlay）。本机 Android 17 实测 overlay
不保证生效：`/system/fonts/NotoColorEmoji.ttf` 仍是系统原版。于是 emoji 能显示（系统自带 Noto
也有这些码位），但画出来是**安卓风格**，不是苹果的。回退点在 6.3 —— 那一版重写模块时，
把 5.0 里的四道保险删掉了。

6.5.2 把 5.0 的做法整套搬回来：

| 保险 | 在哪 | 作用 |
|---|---|---|
| 禁用 GMS 字体下发 | `system.prop` | `/data/fonts` 优先级高于 `/system/fonts`，不禁止就会盖回来 |
| 铺满 emoji 文件名 | `customize.sh` | 解析 `fonts.xml` / `font_fallback.xml`，把系统真正引用的 `NotoColorEmoji` / `NotoColorEmojiLegacy` / `NotoColorEmojiFlags` / `MiSansEmoji` 逐个接管 |
| bind mount | `post-fs-data.sh` | `mount --bind` 到每个 `*Emoji*.ttf` 位点，并 `chcon system_file`；bind 是内核行为，不依赖 KSU 挂载实现 |
| 清缓存 + 关 provider | `service.sh` | 开机后清 `/data/fonts`、主题字体目录、字形缓存，再关掉 GMS FontsProvider |

另外，安装期会清掉自身目录下的 `disable` 标记：用同 id 升级时装了却仍是禁用状态，
是另一种「装了跟没装一样」。

**字体没变**：`Roboto-Regular.ttf` `dcc31ca9…`（69,340,020 B），
`NotoColorEmoji.ttf` `9bacf7c3…`（60,277,864 B）。

装了没效果：模块详情页点「执行」，会现场挂载并打印诊断，同时写到 `/sdcard/emoji_diag.txt`。

从 6.3 / 6.4 / 6.5 过来的话：装 6.5.2 → 卸载 `Chiron × Apple Emoji（类原生）`（id `chiron_ksu_font`）→ 重启。

## 新增的表情

| 码位 | 表情 | 名称 |
|---|---|---|
| U+1FAEA | 🫪 | 变形的脸 |
| U+1FAEF | 🫯 | 打斗云团 |
| U+1FAC8 | 🫈 | 毛怪 |
| U+1FACD | 🫍 | 虎鲸 |
| U+1F6D8 | 🛘 | 山体滑坡 |
| U+1FA8A | 🪊 | 长号 |
| U+1FA8E | 🪎 | 宝箱 |
| U+1F9D1 U+200D U+1FA70 | 🧑‍🩰 | 芭蕾舞者（含 5 档肤色） |

`👯` 戴兔耳朵的人、`🤼` 摔跤选手 及各自的男女版本，17.0 才补上肤色，也一并进字体了。

## 下载哪个

| 文件 | 体积 | 给谁 | 怎么装 |
|---|---|---|---|
| `Chiron-Merriweather_v6.5_AppleEmoji.mtz` | 124.8 MiB | 没 Root，MIUI / HyperOS，字体 + Apple emoji | 本版未改，见 [v6.5](https://github.com/Cheney34/chiron-apple-emoji/releases/tag/v6.5) 附件 |
| `Chiron-Merriweather_v6.5.mtz` | 37.0 MiB | 没 Root，只要字体，不动 emoji | 本版未改，同上 |
| `Chiron_KSU_Font_A17_v6.5.2.zip` | 92.7 MiB | 有 Root（KernelSU / Magisk / APatch），类原生 AOSP | 管理器刷入 → 重启 |

两个 MTZ 只能装一个。KSU 模块只能留一个：6.5.2 安装时会扫描并点名其它也在改同一批字体的模块，
按它给的清单卸掉，再重启。

> 本页只发字体成品。搜狗表情面板的模块已迁到 [apple-input-for-sogou](https://github.com/Cheney34/apple-input-for-sogou)
> （最新 **v2.1.1**，同样升到 Emoji 17.0）；本仓库的 `lsposed-sogou/` 是冻结的 1.x 历史版本，
> 清单仍停在 16.0，不再随字体版本发 APK。

HyperOS / MIUI 建议直接用 MTZ：KSU 模块是照类原生 AOSP 的 `font_fallback.xml` 结构写的，HyperOS 上不一定插得进去。

## 6.5 改了什么

| 项 | 6.4（Emoji 16.0） | 6.5（Emoji 17.0） |
|---|---|---|
| Apple 序列数 | 3808 | **3946**（+138） |
| 字体字形数 | 3842 | 4006 |
| cmap 基字符 | 1445 | 1452 |
| `GSUB` 连字 | 3553 | 3730 |
| MTZ 内 emoji 字体 | 87.8 MB | 92.4 MB |
| KSU 内 emoji 字体 | 57.1 MB | 60.3 MB |

- **位图来源**：npm 的 `emoji-datasource-apple` 停在 16.0.0，没有 17.0 的图。改用
  `iamcal/emoji-data` 的仓库快照（commit `e77759c2`），其 `1faea.png` 与 Emojipedia 的
  `source/apple/453`（iOS 26.4 测试版美术）逐像素一致，确认是苹果原图。
- **正文完全没动**：三份产物里的 `Roboto-Regular.ttf` 仍是同一份，
  69,340,020 B，sha256 `dcc31ca9…`。MTZ 的预览图、KSU 的安装脚本也逐字节保留。
- **档位没变**：MTZ 单档 128 ppem、KSU `32,45,60` 三档真彩，与 6.4 规格一致，
  体积变化只来自新增的 138 条序列。
- **U+F8FF 苹果 logo** 沿用 6.4 的字形，没回退。
- 顺手修了 `emoji-font/build17.py` 里硬编码 `/root/work/` 的中间文件路径（换机器就崩）。

## 字体只管显示，输入是另一条链路

换了字体之后能看见别人发来的 🫪，不代表自己能打出来。**面板里有没有这个键，由输入法自己的
表情清单决定**，字体管不到：

| 键盘 | 面板清单在哪 | 换字体能不能多出 17.0 |
|---|---|---|
| Gboard / 小米键盘 / 系统键盘 | 各自 APK 里编好的数据（`EmojiCompat` 元数据） | ❌ 只能等 App 更新 |
| 搜狗输入法 | `files/sogou/emojipackage/<分组>/info.xml` | ✅ 模块可替换 |

所以「复制粘贴能显示」是字体在起作用，「自己打不出来」是键盘里没这条路，两件事。
想自己打出来，走独立仓库的模块：

- [apple-input-for-sogou **v2.1.2**](https://github.com/Cheney34/apple-input-for-sogou/releases/tag/v2.1.2)
  —— 新增快捷码，打 `pg1`–`pg8` 上屏就是这 8 个新表情（默认开，不依赖面板装没装）。
- [v2.1.1](https://github.com/Cheney34/apple-input-for-sogou/releases/tag/v2.1.1)
  —— 搜狗表情面板的清单：`info.xml` 补 8 条新条目、给 6 个老表情打开肤色，
  payload 3868 → 3911 条目。新条目在各自分组**最末尾**。

也可以完全不装模块，用搜狗自带的「自定义短语」（设置 → 输入设置 → 自定义短语），
缩写写 `pg1`、短语写 🫪，加 8 条。三条路的细节见
[怎么打出新表情](https://github.com/Cheney34/apple-input-for-sogou/blob/main/docs/怎么打出新表情.md)。

## 校验值

| 文件 | 字节 | SHA-256（前 16 位） |
|---|---|---|
| `Chiron-Merriweather_v6.5.mtz` | 38,823,783 | `d139a38d1f7dd28c` |
| `Chiron-Merriweather_v6.5_AppleEmoji.mtz` | 130,835,906 | `184078e19263c8da` |
| `Chiron_KSU_Font_A17_v6.5.2.zip` | 97,234,273 | `fd923fb1a2a11447` |

## 已知限制

| 限制 | 说明 |
|---|---|
| 字体不管输入 | 字体里已经有 17.0 的码位，所以**能显示**；但键盘面板里有没有这个键由输入法决定，**要能打必须另装模块或用自定义短语**，见上面那节 |
| 酷安 / 微博仍是自带字体 | 这类 App 内置 emoji2-bundled 渲染器，任何系统级替换都不生效 |
| Apple 美术资源不再分发 | 仓库只放脚本，位图由 `emoji-font/fetch17.py` 在你本机抓取 |
| 苹果 logo 是商标 | 只做字形替换，未获再分发授权，仅供个人本机使用 |

## 授权

脚本 MIT ｜ Chiron GoRound TC 见上游 ｜ Merriweather 为 SIL OFL 1.1 ｜ Apple Color Emoji 版权归 Apple Inc.
