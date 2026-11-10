# Chiron × Apple Emoji 6.7 / Chiron Merriweather 6.7.1

本次两条线各发一版：**模块 6.7**（三件反馈）、**MTZ 6.7.1**（字重可调回来）。
6.7 这一号只出过 MTZ，模块上一版是 6.6，所以模块这版顺位 6.7。

## 模块 6.7

### 1. 微信 / 抖音输入框没有光标

6.5.1 起模块顺手把正文也换了：`system/fonts/Roboto-Regular.ttf` 里是 66 MB 的
`Chiron GoRound TC VF`，一个可变字体 —— `OS/2.usWeightClass = 330`，`fvar` 默认实例也是 330，
而系统字体配置按 **400** 找它；`gvar` 41 MB，渲染前还得按字重把 5 万个字形实例化一遍。

结果就是打字没光标，公众号页的日期、天气卡片也不刷新（WebView 首屏排版把那段文本整段跳过）。

5.0 / 6.2 那两版只换 emoji、不碰正文，所以从来没有这个毛病。

**这一版把正文字体挪到 `files/`，默认不挂载。** 想换正文，进 WebUI 单独打开。
字体本身也静态化了：删 `fvar` / `gvar` / `STAT`，`usWeightClass` 改 400，69 MB → 28 MB。

### 2. `🙂‍↕️ 🙂‍↔️ 🫨` 显示有误 / 空白

emoji 字体是完好的：4006 字形、3730 条连字，`🙂‍↕️` 的连字字形在 5 个档位里都有位图（抽图确认过）。

真凶是**正文字体抢了组件码位**。Chiron 是 CJK 字体，把 `U+2194 ↔`、`U+2195 ↕`、`U+2640 ♀`、
`U+2642 ♂`、`U+27A1 ➡` 当成全角符号收进了 cmap。系统逐字符挑字体，这几个字符落到正文字体上，
一个 ZWJ 组合就被切成两段，连字不成立 —— 画出来是「彩脸 + 黑白箭头」。
某些界面把 `U+FE0F` 去掉时，emoji 字体里 `U+2195` 的占位字形是 1×1 透明位图，于是变成一段空白。

**改法**：从正文字体 cmap 里摘掉这 5 个码位。只重写 cmap 表，
`glyf` / `loca` / `hmtx` / `GSUB` / `GPOS` / `name` 一字节没动。
这 5 个字符此后只有 emoji 字体一个来源，组合能落回同一个字体，连字生效。

### 3. WebUI

模块详情页多一个入口：

- **状态**：emoji 接管了几个位点、正文字体挂没挂、当前开关
- **表情包**：`Apple 17.0` ↔ `系统原厂`（选原厂会把模块内 emoji 字体移出 overlay 目录）
- **正文字体**：`不换（默认）` ↔ `换成 Apple 字体`
- **操作**：立即重挂载 / 运行诊断 / 导出日志到 `/sdcard/Download/` / 重启

需要 KernelSU 的 WebUI 接口；Magisk 没有这个，仍可以用模块详情页的「执行」按钮。

## MTZ 6.7.1：字重可调回来

6.7 为了修「WebView 里日期、天气不渲染」，把正文静态化了（`fvar` / `gvar` / `STAT` 全删，
`<fontWeight>` 收成 1 档）。代价是 MIUI 的「字体粗细」滑块锁死 —— 滑块靠 `wght` 轴做
无级插值，轴没了就没得插。

6.7.1 把完整 `wght 150–700` 换回来，只保留 6.7 那一刀有用的：`OS/2.usWeightClass`
`330 → 400`、重算 `head.checkSumAdjustment`（实测 `0xB1B0AFBA`），
`description.xml` 恢复 12 档、`<version>` 写 `6.7.1`。

风险照旧：轴回来，公众号日期空白可能复发。先拖滑块，再开公众号文章验。

## 装法

模块（KSU）：

```
KSU Manager → 模块 → 从本地安装 → Chiron_KSU_Font_A17_v6.7.zip → 重启
```

MTZ（免 Root）：

```
主题 → 我的 → 从存储导入 → Chiron-Merriweather_v6.7.1_AppleEmoji.mtz → 应用 → 重启
```

装完确认模块状态：

```
su -c cat /data/adb/chiron_apple_emoji/post-fs.log | tail -4
```

应该看到 `settings: EMOJI=1 BODY=0` 和 `VERDICT OK`。

## 已知

`🫨`（U+1FAE8，Emoji 15.0）在字体里是有的、位图也在。如果它仍然显示成安卓样式或空白，
那是那个 App 自己在用 Google 的 EmojiCompat 下发字体画表情（模块已经用
`ro.com.google.gmscore.font_provider.disabled=1` 和删 `/data/fonts` 去堵），
与系统字体无关 —— 把 WebUI 里的诊断导出发我，我按日志再判。

## 包

模块 6.7：

- `Chiron_KSU_Font_A17_v6.7.zip` — 209,945,622 B
- emoji：`system/fonts/NotoColorEmoji.ttf` 198,963,820 B，5 档 38/53/70/96/150 px
- 正文：`files/Roboto-Regular.ttf` 28,111,052 B（静态 wght=400，默认不挂）

MTZ 6.7.1：

- `Chiron-Merriweather_v6.7.1.mtz` — 38,823,887 B（纯字体）
- `Chiron-Merriweather_v6.7.1_AppleEmoji.mtz` — 130,835,966 B（+ Apple emoji）

（这一版是在进程创建全崩的机器上做的：PowerShell 直接改字体字节、进程内 `ZipFile` 重打包，
没能跑 `fontTools` 复核。字体表结构与 6.6 / 6.7 逐字节对齐，`head.checkSumAdjustment` 已重算。）
