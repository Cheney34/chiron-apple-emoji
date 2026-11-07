# Chiron × Apple Emoji 6.5

表情库升到 **Emoji 17.0 / iOS 26 字形**。正文一个字没动。

Unicode 17.0 于 2025-09 定稿，苹果在 iOS 26.4 测试版里把这批图画补齐了。这一版把苹果的
正式美术全部收进字体 —— 不是第三方仿画，也不是 Google Noto 的设计。

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
| `Chiron-Merriweather_v6.5_AppleEmoji.mtz` | 124.8 MiB | 没 Root，MIUI / HyperOS，字体 + Apple emoji | 设置 → 主题 → 字体 → 从本地导入 |
| `Chiron-Merriweather_v6.5.mtz` | 37.0 MiB | 没 Root，只要字体，不动 emoji | 同上 |
| `Chiron_KSU_Font_A17_v6.5.zip` | 92.7 MiB | 有 Root（KernelSU / Magisk / APatch），类原生 AOSP | 管理器刷入 → 重启 |

两个 MTZ 只能装一个。装 KSU 模块之前先卸载或禁用其它字体模块，两个模块抢同一批文件必炸。

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

## 搜狗输入法面板

系统字体换了，搜狗表情面板里仍是它自己的包。要让面板也是这套 17.0 的图，用独立仓库的模块：
[apple-input-for-sogou v2.1.1](https://github.com/Cheney34/apple-input-for-sogou/releases/tag/v2.1.1)
—— `info.xml` 补了 8 条新条目、给 6 个老表情打开肤色，payload 从 3868 → 3911 条目。

## 校验值

| 文件 | 字节 | SHA-256（前 16 位） |
|---|---|---|
| `Chiron-Merriweather_v6.5.mtz` | 38,823,783 | `d139a38d1f7dd28c` |
| `Chiron-Merriweather_v6.5_AppleEmoji.mtz` | 130,835,906 | `184078e19263c8da` |
| `Chiron_KSU_Font_A17_v6.5.zip` | 97,224,314 | `1e45870f9a55af4f` |

## 已知限制

| 限制 | 说明 |
|---|---|
| 新表情能不能打出来看输入法 | 字体里已经有 17.0 的码位，但输入法的候选/面板是否收录由 App 决定。系统层（微信、短信、备忘录）复制粘贴即可显示 |
| 酷安 / 微博仍是自带字体 | 这类 App 内置 emoji2-bundled 渲染器，任何系统级替换都不生效 |
| Apple 美术资源不再分发 | 仓库只放脚本，位图由 `emoji-font/fetch17.py` 在你本机抓取 |
| 苹果 logo 是商标 | 只做字形替换，未获再分发授权，仅供个人本机使用 |

## 授权

脚本 MIT ｜ Chiron GoRound TC 见上游 ｜ Merriweather 为 SIL OFL 1.1 ｜ Apple Color Emoji 版权归 Apple Inc.
