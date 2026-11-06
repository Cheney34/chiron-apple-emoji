# Chiron Emoji 6.4

这版只改一个字形：**U+F8FF**。

U+F8FF 是苹果系统里唯一的私用区（PUA）码位。iOS / macOS 上打出来是那个苹果标志 —— 备忘录、Pages、Keynote、Xcode 里都见得到，它不在 Unicode 正式区里，纯属苹果自家约定，安卓这边没有任何字体提供。

Chiron GoRound TC 原字体在这个码位放的是一颗带字母 N 的五角星（作者自己的标记），所以换上这套字体之后，从苹果设备复制过来的 会变成星号。6.4 把轮廓换成苹方里的苹果 logo。

## 下载哪个

| 文件 | 体积 | 给谁 | 怎么装 |
|---|---|---|---|
| `Chiron-Merriweather_v6.4_AppleEmoji.mtz` | 120.4 MiB | 没 Root，MIUI / HyperOS，字体 + Apple emoji | 设置 → 主题 → 字体 → 从本地导入 |
| `Chiron-Merriweather_v6.4.mtz` | 36.9 MiB | 没 Root，只要字体，不动 emoji | 同上 |
| `Chiron_KSU_Font_A17_v6.4.zip` | 89.6 MiB | 有 Root（KernelSU / Magisk / APatch），类原生 AOSP | 管理器刷入 → 重启 |

两个 MTZ 只能装一个。装 KSU 模块之前先卸载或禁用其它字体模块，两个模块抢同一批文件必炸。

HyperOS / MIUI 建议直接用 MTZ：KSU 模块是照类原生 AOSP 的 `font_fallback.xml` 结构写的，HyperOS 上不一定插得进去。

## 6.4 改了什么

| 项 | 6.3_refix | 6.4 |
|---|---|---|
| U+F8FF 字形 | 带 N 的五角星 | 苹果 logo |
| 轮廓来源 | Chiron 原厂 | PingFangSC-Regular（同为 upem 1000，不用缩放） |
| 字宽 adv | 658 | 1000（占满一个全角） |
| 垂直范围 | y 20 … 564 | y -59 … 777 |

- **不随字重变化**：`gvar` 里这个码位本来就没有 delta，150–700 全档同一个形状。加不出变化的就不假装有 —— 苹果自家字体里这个标志也是单字重。
- **其余一个字都没动**：cmap 46,046 码位、50,551 字形、hhea 1078 / -348、typo 976 / -246 / 200、`wght` 轴 150–700 全部与 6.3 一致。用 28 / 44 / 76 px × 150 / 330 / 500 / 700 四档字重逐像素比对中英混排样本，差异像素数 **0**。
- **三个渠道的字体是同一份**：两个 MTZ 和 KSU 模块里的 `Roboto-Regular.ttf` 完全一致（sha256 `dcc31ca9…`，69,340,020 B），不会再有某个渠道字形没跟上。
- 6.3_refix 的星号重画、`@` 上移、行高压到 1.280 em 全部沿用，没有回退。

## 校验值

| 文件 | 字节 | SHA-256（前 16 位） |
|---|---|---|
| `Chiron-Merriweather_v6.4.mtz` | 38,721,651 | `f93f455c23d41f77` |
| `Chiron-Merriweather_v6.4_AppleEmoji.mtz` | 126,213,598 | `99f3bae0bd2798ef` |
| `Chiron_KSU_Font_A17_v6.4.zip` | 93,931,990 | `c2f6e6e9c6a5465f` |

## 已知限制

| 限制 | 说明 |
|---|---|
| 只有本套字体认这个码位 | 安卓默认字体、其它第三方字体在 U+F8FF 上是空白或豆腐块。App 自己画的图标字体不受影响 |
| 只修了私用区这一个码位 | 苹果另有一批「只有 iOS 有」的符号（SF Symbols 系列）走的是别的机制，不在字体里，做不进来 |
| 徽标是 Apple 的商标 | 这里只做字形替换，未获再分发授权，仅供个人本机使用 |
| 酷安 / 微博仍是自带字体 | 这类 App 内置渲染器，任何系统级替换都不生效 |

## 授权

脚本 MIT ｜ Chiron GoRound TC 见上游 ｜ Merriweather 为 SIL OFL 1.1 ｜ Apple logo 与 Apple Color Emoji 版权归 Apple Inc.
