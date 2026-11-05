# Chiron × Apple Emoji · 类原生 KSU 字体模块

给类原生 AOSP（Infinity X / Android 17）用的字体模块。一次刷入，同时换掉三样东西：

| 内容 | 换成什么 |
|---|---|
| 中文字体 | Chiron GoRound TC |
| 西文与数字 | Merriweather（合并进同一个字体文件） |
| Emoji | Apple 彩色 emoji（RGBA 真彩，32/45/60 三档位图） |

## 装之前

- KernelSU / Magisk / APatch 任一，已 root
- **先卸载或禁用其它字体模块**，两个模块抢同一批文件必炸
- 备份当前系统，或至少确认你会用 KSU 安全模式

## 安装

KSU Manager → 模块 → 从本地安装 → 选 `Chiron_KSU_Font_A17_v6.3_refix.zip` → 重启。

安装界面会打印探测结果，重点看三行：

```
- 系统默认字体：Roboto-Regular.ttf
- 配置文件：/system/etc/font_fallback.xml
- 已在中文家族插入字体（1795 → 1805 行）
```

如果看到 `! 配置里没有 zh-Hans/zh-Hant 家族`，说明中文不会变，把 `/data/local/tmp/chiron_font.log` 发我。

## 装完怎么验证

```sh
su -c "cat /data/local/tmp/chiron_font.log"
```

日志会列出：

- `/system/fonts/Roboto-Regular.ttf` 的字节数（应该接近 69 MB，说明覆盖成功）
- `/system/fonts/NotoColorEmoji.ttf` 的字节数（应该接近 57 MB）
- 中文家族首位指向哪个字体
- `/data/fonts` 是否为空（非空说明 GMS 下发的字体会盖掉本模块）

肉眼验证：打开设置看中文，字形应该是圆角的 Chiron；随便打个 😀 看是不是苹果那版。

## 出问题怎么办

**开不了机 / 开机卡 Logo**：长按音量下键开机，进 KSU 安全模式（所有模块禁用），进系统后卸载本模块。

**字体变豆腐块或没变化**：先看日志。如果日志里 `font_fallback.xml` 那行显示「未改写」，说明你的 ROM 结构和我预期不同，把 `/system/etc/font_fallback.xml` 发我。

**中文没变但英文变了**：正常，说明中文家族的插入没成功（锚点没匹配到），发我配置文件。

## 技术说明

### 为什么不改 fonts.xml

Android 15 起 `fonts.xml` 已废弃，Minikin 真正读的是 `font_fallback.xml`：

> Starting in Android 15, variable fonts are rendered at runtime... vendors must add new variable font configurations to **font_fallback.xml instead of fonts.xml, as fonts.xml is being deprecated**.

网上 2019–2022 年那批字体模块教程（包括少数派那篇）改的都是 `fonts.xml`，在你的系统上不会生效。

### 西文怎么换的

AOSP 的 `sans-serif` 家族在 Android 15+ 是这样写的：100–900 九个字重**全部指向同一个文件** `Roboto-Regular.ttf`，再用 `<axis>` 指定 `ital` / `wdth` / `wght` 的实例值。

所以只要把我们的字体改成同名覆盖进去，**配置一个字都不用改**，九个字重全部生效——Chiron 本身是可变字体，靠 `wght` 轴（150–700）响应。

### 行高为什么是 1.280 em

| 字体 | hhea ascent / descent | 行高 |
|---|---|---|
| 系统 Roboto | 1900 / -500（upem 2048） | 1.171 em |
| 系统 NotoSansCJK | 1160 / -320（upem 1000） | 1.480 em |
| Chiron 原厂 | 1138 / -288 | 1.426 em |
| **本模块** | **1000 / -280** | **1.280 em** |

Chiron 原厂行高 1.426 比 Roboto 松 22%，只换西文会让行距明显变松。压到 1.280 后：

- 比 Roboto 松 9%（16 sp 下差 1.7 px，看不出来）
- 比系统中文的 1.480 反而更紧凑
- 字框中心 360，数字视觉中心 356，偏差 4 单位 —— 状态栏数字不会下沉

压缩是有代价的：全字体 46,030 个有轮廓的字形里，只有 45 个（0.10%）的 `yMax` 超过 1000，全是越南语带声调的拉丁字母（Ẳ Ằ Ắ Ṹ Ṍ …），中文和常规西文都不受影响。

### emoji 为什么从 188 MB 裁到 57 MB

```text
原版  188.8 MB  RGBA 真彩  5 档 ppem（32 / 45 / 60 / 82 / 128）
本模块 57.1 MB  RGBA 真彩  3 档 ppem（32 / 45 / 60）
纯色版 61.7 MB  P 模式 256 色  5 档    ← 会发糊，已弃用
MTZ 版 18.6 MB  P 模式 256 色  1 档    ← 缩放必糊，已弃用
```

只裁掉 82 和 128 两档高位图。Android 渲染 emoji 的常规尺寸在 16–48 px，32/45/60 三档足够覆盖；超过 60 px 才会用 60 档放大，那种场景基本只有超大表情预览。

色彩保持 RGBA 真彩：😀 在 32 ppem 档有 900 色，不是 256 色那份的 119 色。

## 文件清单

```
Chiron_KSU_Font_A17_v6.3_refix.zip   92 MB
├── module.prop
├── customize.sh               探测文件名 + 改 font_fallback.xml
├── post-fs-data.sh            写诊断日志
├── uninstall.sh
├── META-INF/com/google/android/{update-binary,updater-script}
└── system/fonts/
    ├── Roboto-Regular.ttf     69 MB  Chiron + Merriweather
    └── NotoColorEmoji.ttf     57 MB  Apple emoji
```

## 更新日志

- **v6.3_refix** 星号 `*` 重画：保留直角六角星造型，外框改为 388×366、中心 531、adv 452，与 Roboto 原星号（394×361、中心 528.5）对齐。上一版 400 高、中心 470，在拨号盘里比原来的星号高 11%、位置低 0.06 em，看着偏大偏下。
- **v1.3** 星号从圆头三杠改为直角六角星。
- **v1.2** 中文走 `font_fallback.xml` 家族首位插入，不替换 NotoSansCJK。

模块**不修改 system 分区**，全靠 KSU 的 magic mount 覆盖；卸载后系统字体自动恢复，不会留下任何残留。

## 许可

- 代码（脚本）：MIT
- Chiron GoRound TC：见上游授权
- Merriweather：SIL OFL 1.1
- Apple emoji 位图：版权归 Apple，仅供个人使用，不得再分发
