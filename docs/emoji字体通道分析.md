# 为什么 MiSans 用户「酷安/微博还是安卓 emoji」，而你的 mtz 包有效

> 分析对象：AppleEmoji_Chiron_v5.0（CBDT 位图版）在 HyperOS 4.0 / Android 17 上的表现差异
> 结论一句话：**不是字体坏了，是这三个 App 走的不是同一条「字体通道」。**

---

## 一、先厘清：Emoji 在 Android 上有三层通道

Android 画一个 emoji，不一定是「去 /system/fonts 找 NotoColorEmoji.ttf」。实际有三条路：

| 层 | 通道 | 字体从哪来 | 换 `/system/fonts` 能不能管到 |
|---|---|---|---|
| L1 | 平台文本渲染（Minikin + HarfBuzz + FreeType） | `/system/fonts/*.ttf`，按 `fonts.xml` 的 `und-Zsye` family fallback | ✅ 能 |
| L2 | **可更新系统字体**（Android 12+ FontManager） | `/data/fonts/`，由 GMS FontsProvider 下发、按需更新 | ❌ 管不到（除非删目录 + 禁 provider） |
| L3 | **App 自带渲染器 / 自带 emoji 字体** | APK 内 `assets`，或 `androidx.emoji2:emoji2-bundled`（约 10.1MB） | ❌ 完全管不到 |

**「某些 App 生效、某些不生效」= 这些 App 落在不同的层。**

- 微信、QQ、系统 UI、设置 → 基本都在 **L1**，换字体立刻变。
- 酷安、微博这类「信息流 + H5 + 自绘富文本」的 App → 大量落在 **L2 / L3**，系统字体换了它也不看。

这不是玄学，是 Google 自己写在文档里的：

> 从 Android 13（API 33）开始，系统表情符号渲染程序使用的字体文件**已从基于 PNG 的文件更改为基于矢量的文件**（COLRv1）。Android 15 移除了旧版 PNG 字体 `NotoColorEmojiLegacy.ttf`。
> —— [Android 15 行为变更（所有应用）](https://developer.android.google.cn/about/versions/15/behavior-changes-all)

> **在 Android 15 及更高版本中，EmojiCompat 默认处于停用状态**……系统通过**可更新的系统字体**实现了全覆盖。新 API `setUseAfterUpdatableSystemFonts(boolean)` 默认值为 `false`；关闭时，EmojiCompat 在 Android 15+ 上**不执行任何操作**，App 改用「可更新系统字体」绘制表情符号。
> —— [Emoji2 版本说明 1.6.0](https://developer.android.google.cn/jetpack/androidx/releases/emoji2)

这两条合起来就是本次问题的全部背景：
1. 系统 emoji 已经换代成**矢量 COLRv1**，PNG 位图成了「旧格式」；
2. 新一代 App 的 emoji 来源是**可更新系统字体**，不再是 `/system/fonts` 里那个文件。

---

## 二、我们 v5 字体的实测体检（这是关键差异）

对 `NotoColorEmoji_v5.ttf` 跑了 fontTools：

```
表结构        CBDT / CBLC / GSUB / glyf / cmap …（无 COLR 表）
unitsPerEm    2048
glyph 总数    3842，其中带轮廓的 = 0，全部是空轮廓
位图档位      5 档：32 / 45 / 60 / 82 / 128 px
cmap 单码位   1445 个
GSUB 连字     1 个 lookup / 3553 条 ccmp（家庭、肤色、旗帜、键帽全靠它）
文件大小      115.9 MB
```

对比系统原版（来自你设备上的 diag）：

```
/system/fonts/NotoColorEmoji.ttf        2,992,136 字节
/system/fonts/NotoColorEmojiFlags.ttf     872,756 字节
/system/fonts/NotoColorEmojiLegacy.ttf   （ignore="true"，保留但忽略）
```

**2.99MB vs 官方 PNG 版的 10.1MB** —— 这个体积差本身就说明：系统那份已经是 **COLRv1 矢量版**，不是 PNG。

由此得到三条硬结论：

1. **格式代差**：我们给的是「Android 12 时代的 PNG 位图格式」，系统在用的是「Android 13+ 的矢量格式」。L1 层两者都认，所以大部分 App 正常；
   **但只认 COLRv1 的渲染路径（部分 WebView 内核、Flutter/游戏引擎、自绘文本）遇到 CBDT-only 字体，会直接跳过这个 family**，回落到它自己的那份 → 你看到的就是「还是安卓 emoji」。
2. **空轮廓**：3842 个 glyph 全部 `numberOfContours = 0`。任何不支持 CBDT 彩色位图的渲染器，拿到的是一堆**空白字形**——不是黑白，是「什么都不画」。
3. **强依赖 GSUB**：cmap 只有 1445 个单码位，其余 3553 条组合全靠 `ccmp` 连字。**不做 shaping 的渲染器**（直接按码位查 cmap）会把 👨‍👩‍👧 / 🇨🇳 / 👍🏽 拆开，表现成「有的 emoji 是苹果、有的是安卓、旗帜变成 CN 两个字母」。

---

## 三、为什么你的包在酷安/微博有效，他的不行

差异不在字体内容，在**分发形态**：

| | 你的包（mtz / 主题字体） | 他的（Magisk / KSU 模块） |
|---|---|---|
| 落点 | `/data/system/theme/fonts/` | `/system/fonts/`（overlay 或 bind） |
| 谁加载 | MIUI FontManager（**运行时字体覆写**） | framework 启动时扫描 fonts.xml |
| 应用时动作 | 主题切换会**重启进程 + 清字体缓存** | 只换文件，进程内缓存的字体不变 |
| 能不能覆盖 H5/自绘 App | 多数能（走了 FontManager 的全局覆写） | 经常不能 |
| 风险 | 低（可随时切回默认） | 高（bind 失败就静默无效） |

你自己的设备就有一个现成的反例，在 `emoji_diag.txt` 里：

```
[未接管] /system/fonts/NotoColorEmoji.ttf  2992136 字节  <-- 系统在用这份
[未接管] /system/fonts/NotoColorEmojiFlags.ttf  872756 字节  <-- 系统在用这份
live: /system/fonts/NotoColorEmoji.ttf = 2992136 bytes
```

**模块根本没挂上去**（post-fs.log 里连 `bind OK/FAILED` 都没打印，说明跑的是早期版本、且 overlay 被 HyperOS 的 EROFS 逻辑分区挡掉了）。
你在酷安微博看到的苹果 emoji，**来自 mtz，不是来自模块**。

这一点非常重要：它说明「mtz 通道有效、模块通道在 HyperOS 4.0 上不可靠」是**实测结论**，不是推测。

---

## 四、给 MiSans 用户的四个解法（按落地难度排序）

### 方案 1：换成 mtz 形态分发（最稳，已验证）
把 emoji 字体并进一个主题字体包，走「设置 → 主题 → 字体」安装。
- 优点：走 FontManager，覆盖率高，可一键还原；
- 缺点：需要用户有主题商店权限，且会连带换掉正文字体（可以把正文做成和 MiSans 一致的度量）。

### 方案 2：模块里补 `fonts.xml` 覆写（根治 L1 层）
只 bind `.ttf` 是不够的——**family 配置不改，某些渲染器就永远找不到你的字体**。
业界做法（MakeFontsGreatAgain）就是连 `fonts.xml` 一起替换：

```xml
<!-- 原来是 ignore="true"，被跳过 -->
<family lang="und-Zsye" ignore="true">
    <font weight="400" style="normal">NotoColorEmojiLegacy.ttf</font>
</family>

<!-- 改成：去掉 ignore，指向我们的文件 -->
<family lang="und-Zsye">
    <font weight="400" style="normal">NotoColorEmoji.ttf</font>
</family>
```
并把 emoji family 在 fallback 链里**前移到 `sans-serif` 之后第一位**。
> 风险：fonts.xml 写错会起不来。建议做成「读原文件 → 正则替换 → bind 到原路径」，而不是整份替换。

### 方案 3：清掉 L2 通道的抢占源
```sh
rm -rf /data/fonts
pm disable com.google.android.gms/com.google.android.gms.fonts.provider.FontsProvider
pm disable com.google.android.gms/com.google.android.gms.fonts.update.UpdateSchedulerService
```
（我们模块的 `service.sh` 已经做了，但只在安装后的第一次开机执行；用户中途装模块时容易漏。）

### 方案 4：确认这些 App 是不是 L3（自带字体）
对目标 App 直接查 APK：
```sh
APK=$(pm path com.coolapk.market | sed 's/package://')
unzip -l "$APK" | grep -iE 'emoji|noto'
```
如果命中 `assets/.../NotoColorEmoji*.ttf` 或 `res/raw/emoji*`，那就是**App 自带**，任何系统层替换都无效，只能等 App 更新或在 App 内设置。

---

## 五、给社区用户的三步自检（可直接发）

1. **先分清是不是系统问题**：把同一个 emoji 复制到「设置 → 关于手机」的搜索框里看。
   - 那里是苹果 → 系统已生效，问题在 App，别再折腾字体；
   - 那里也是安卓 → 字体没接管，跑一次模块诊断。
2. **跑诊断**：模块详情页点「执行」，把 `/sdcard/emoji_diag.txt` 发回来。
   重点看 `[已接管]/[未接管]` 和 `/data/fonts` 是否存在。
3. **确认 App 类型**：酷安、微博的正文/评论区大量是 H5 或自绘富文本，本身就绕开系统字体。
   清一次 App 缓存 + 强制停止再开，能排除缓存；清完还是安卓，就是 App 自带渲染，属于「改不了」的那一类。

---

## 六、一句话版本（发社区用）

> 不是字体包的问题。安卓 13 起系统 emoji 已经从 PNG 位图换成了矢量字体，15 之后 App 更是直接改用「可更新系统字体」，不再读 `/system/fonts` 那个文件。
> 酷安、微博这类 App 走的是自绘/自带字体的通道，换系统字体对它们天然无效——你可以用「设置里搜一个 emoji」来验证：设置里是苹果、App 里是安卓，就说明系统已经生效、是 App 自己的事。
> 想覆盖它们，只有两条路：用主题字体（mtz）形态安装，或者等 App 自己更新。

---

*数据来源：本机 fontTools 实测 + 设备 diag 日志 + Android Developers 官方行为变更文档（Android 15 / Emoji2 1.6.0）。*
