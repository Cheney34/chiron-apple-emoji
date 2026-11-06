# lsposed-sogou

把搜狗输入法的表情面板，整个换成 Apple emoji。**不需要 root，不需要改搜狗 APK。**

```
LSPosed 模块（本仓库） ──广播──▶ 搜狗进程内的 Receiver
                                      │
                                      ├─ 用 context.filesDir 写 emojipackage/
                                      ├─ 备份原厂副本到 .ios-emoji-backup
                                      └─ hook 放开面板横向滑动
```

## 为什么不需要 root

搜狗的表情面板不是内置资源，而是**运行时从 `files/sogou/emojipackage/` 读的目录**：

```
/data/data/com.sohu.inputmethod.sogou/files/sogou/emojipackage/
    3_10000/
        emoji/          20000.png 20001.png …  （64×64，表情位图）
        info.xml        该组清单：unified 码位、名称、supportSkin
        smileys_emotion.png   底部 tab 图标（84×84）
        version.json    <Version text="16.0"/>
```

只要往这个目录里放东西，搜狗自己就会读。难点在于 scoped storage 下外部 App 写不进别人的
`filesDir` —— 所以走 LSPosed，**在搜狗进程内部**执行写入，用的是搜狗自己的 `Context`。

## 目录

```
src/com/chiron/iosemoji/
    HookEntry.java       入口，hook Application.attach(Context)
    EmojiService.java    进程内写文件、备份、还原
    GestureHook.java     放开面板左右滑动
    GroupFilterHook.java 摘掉搜狗内置的「组合」「拼装」分组
    LogoHook.java        输入「苹果」/「pg」上屏成苹果标志 U+F8FF
    MainActivity.java    三个按钮 + 连接检查
    Protocol.java        常量
manifests/               10 个分组的 info.xml（纯文本清单）
icons/                   10 个自绘 tab 图标（SF Symbols 风格，84×84）
tools/make_payload.py    用本地素材生成 payload.zip
assets/xposed_init       入口类名
```

## 构建

```bash
# 1. 准备依赖
#    XposedBridgeAPI-82.jar 放到 libs/，见 libs/README.md

# 2. 生成 payload.zip（含 Apple 位图，不随仓库分发）
python3 tools/make_payload.py --src /path/to/img-apple-160 --out assets/payload.zip

# 3. 编译
./build.sh
```

产物在 `build/app-signed.apk`。

> **签名**：`build.sh` 默认生成调试签名。如果你要覆盖安装某个已分发的版本，
> 必须用**同一份 keystore**，否则 Android 会拒绝升级。用 `KEYSTORE=/path/to.k` 指定。

## 安装

1. LSPosed 里启用模块，作用域勾选「搜狗输入法」；
2. 打开模块 App，点「安装全部」——它会写文件并杀掉搜狗进程；
3. 重新唤起输入法。

验证：`adb shell ls /data/data/com.sohu.inputmethod.sogou/files/sogou/emojipackage/`
应该能看到 `3_9000000010000` 这样的目录，且第一个是笑脸。

## 四个 hook 分别在解决什么

### 1. 写文件（EmojiService）

模块 App 发广播 → 搜狗进程里的 `Receiver` 收到 → 解压 `assets/payload.zip` 到 `filesDir`。
原厂文件在第一次覆盖前备份到 `files/sogou/.ios-emoji-backup/<分组id>/`，
**按分组 id 去重，只留最早的那份**，避免多次安装把「已被替换的版本」当成原厂备份。

### 2. 横向滑动（GestureHook）

搜狗面板本来就能滑，但 `EmojiKeyboardView.showSlideAnimation()` 里把
`NoScrollViewPager.slide` 锁了 900ms —— 动画期间不响应，快速翻页会「粘住」。
hook `setScrollable()` 强制 `slide=true`，并跳过那段动画。

### 3. 摘掉内置分组（GroupFilterHook）

搜狗 APK 里有两份资产清单，每次进程启动 `ExpressionUtil.w1()` 都校验并重新解压：

```xml
<!-- assets/exp_emoji_group -->
<exppkg type="combination" chineseName="组合" id="2">
<!-- assets/assemble_emoji_info -->
<exppkg type="assemble" chineseName="拼装" id="-2">
```

**删目录没用，重启就回来。** 所以从两个必经之路拦：

- `java.io.File.list()` —— 路径是 `…/emojipackage` 时，把 `2_xxx`、`-2_xxx` 从返回数组里摘掉。
  搜狗所有分组枚举（`m0()` 返回 SparseArray、`n0()` 返回 ArrayList）都先调 `list()`，
  在这一层过滤，上层的排序、分页、底部 tab 全部跟着消失；
- `ExpressionUtil.u(AssetManager, src, dst)` —— 上一步让 `m0()` 看不到内置包后，
  `w1()` 会误判成「本地缺失」而重新解压，这里对这两个分组直接返回 `true`，不写盘。

两个 hook 都不删任何文件，在 LSPosed 里取消勾选就完全恢复原样。

### 4. 输入「苹果」/「pg」出苹果标志（LogoHook）

`U+F8FF` 是苹果系统里**唯一**的私用区码位，iOS / macOS 上打出来就是苹果标志。
Chiron 6.4 起这个码位已经换成苹果 logo（此前是 Chiron 原厂带 N 的五角星）。

触发词**全等匹配**，命中后在上屏前把整串换掉：

```
commitText("苹果logo", 1)   →   commitText("\uF8FF", 1)
commitText("pgl",      1)   →   commitText("\uF8FF", 1)
```

默认只收**显式写法**（`苹果logo` `苹果标志` `pgl` `pglogo` 及其常见大小写）。
不要往 `TRIGGERS` 里放 `"苹果"`：那样这个词就永远打不出来了，而且会和下面
「自定义短语」那条路打架——用户点选候选「苹果」之后又被换成 logo，
看起来像是候选失效。

挂载点是 `InputMethodService.getCurrentInputConnection()`，拿到 IME 侧的
`InputConnection` 之后，对它**实际实现的类**做 `hookAllMethods("commitText")`。
不包装成 `InputConnectionWrapper` 子类，是因为 API 33 起多了
`commitText(CharSequence, int, TextAttribute)` 这个重载，包装类只会转发到 target
的三参方法、绕过两参重写；直接 hook 实现类能把所有重载一次盖住，签名里也不用
引用 API 33 才有的 `TextAttribute`（否则 minSdk 26 的机器上类校验可能出问题）。

**为什么不往候选条里插一条**：搜狗的候选是 native 引擎算出来的
（`libSogouIME` 一类），Java 侧只负责把算好的字符串塞进候选 View。想凭空加一条，
得复刻它的候选对象（文本 + 类型 + 编码 + 点击后回传的 id），这套结构每个版本都在变，
对不上就崩输入法。上屏这一层只改一个字符串参数，不碰搜狗任何私有类。

**想要「候选条里直接出现 logo」**（iOS 文本替换那种体感）：用搜狗自带的
「设置 → 高级 → 自定义短语」，编码填字母，短语内容填你要上屏的东西：

| 编码 | 短语内容 | 效果 |
|---|---|---|
| `pg` | `🍎` | 打 pg，候选条里出红苹果 |
| `pg` | `\uF8FF`（即 ） | 打 pg，候选条里出苹果标志 |
| `pingguo` | 同上两条 | 打全拼也会出这两条 |

同一个编码可以挂多条，候选条里并列显示；候选条和上屏都用系统字体渲染，
所以 `U+F8FF` 会直接显示成苹果标志。这条路**不需要本模块参与**，
编码位只认字母数字，所以中文触发词（「苹果」两个字当编码）走不了——
那只能用上面的 `LogoHook`，且替换串要是固定值，做不到「两条候选让你选」。

限制：

- 只有当前字体带这个字形时才显示 logo，即 **Chiron 6.4 及以上**；换回系统字体就是豆腐块；
- 一旦 `TRIGGERS` 里留着 `"苹果"`，你就再也打不出「苹果」这两个字了。
  还要正常输入这个词的话，把它删掉，只留 `"苹果logo"`、`"pgl"` 这类显式写法；
- 少数 App 自带字体（不是系统字体），私用区会显示成方块；
- 侧滑输入、语音输入一般也走 `commitText`，同样会被替换。

## 分组顺序

目录名是 `{分组id}_{排序值}`，`ExpressionUtil` 用 `lastIndexOf("_")` 切开，
`Integer.parseInt` 得 id、`Long.parseLong` 得排序值，然后**排序值大的排前面**。

搜狗内置包用的是 `System.currentTimeMillis()`（约 1.79e12），
所以本项目给的排序值在 9.0e12 量级，保证笑脸永远第一：

| 分组 | id | 目录名 |
|---|---|---|
| 笑脸 | 3 | `3_9000000010000` |
| 人物 | 4 | `4_9000000009000` |
| 旗帜 | 12 | `12_9000000008000` |
| 符号 | 11 | `11_9000000007000` |
| 动物 | 6 | `6_9000000006000` |
| 食物 | 7 | `7_9000000005000` |
| 地点 | 8 | `8_9000000004000` |
| 活动 | 9 | `9_9000000003000` |
| 物品 | 10 | `10_9000000002000` |
| 组件 | 5 | `5_9000000001000` |

## 踩过的坑

| 现象 | 原因 |
|---|---|
| 旗帜、键帽、组合表情点不动 | `unified` 必须用**下划线**（`1F62E_200D_1F4A8`），用横线搜狗认不出，885/2067 条失效 |
| 🈶 🈯 🉐 显示成白底黑字小方块、宽度窄 17% | 这类字符默认 emoji 呈现，标准序列不带 `FE0F`，被正文中文字体抢先渲染。给 1182 条单码位补 `_FE0F` |
| tab 图标是彩色 emoji 贴图 | 搜狗读的是分组目录下的 `<group>.png`（84×84），不是 APK 内资源。换成自绘线稿即可 |
| 分组顺序不对 | 排序值是 13 位数，早期用 `10000` 这种量级，永远排最后 |

## 限制

- **没有 14 键**。10.32.21 的 `resources.arsc` 里只有九键 / 全键 / 大九键 / 双拼 / 手写 / 笔画，
  键位映射在 native 拼音引擎 `.so`，Java 侧只传 `keyboardType` 整数。想改只能反汇编 ARM64，
  无法验证、风险高，本项目不做。
- **部分 emoji 点不出来**。搜狗的表情白名单停在 Unicode 15.0，15.1+ 的 36 条
  （🍋‍🟩 🍄‍🟫 🫩 🪉 🪏 🇨🇶 等）没有词条。字体里有，搜狗不给入口。

## 逆向参考

目标是搜狗输入法 `com.sohu.inputmethod.sogou`（测试版本 10.32.21）。关键类：

| 类 | 作用 |
|---|---|
| `com.sogou.expressionplugin.expression.ExpressionUtil` | `m0()` `n0()` 扫目录；`w1()` 校验内置包；`u()` 解压单个文件 |
| `com.sogou.expressionplugin.expression.b` | 分组对象，`compareTo` 按 `l`（排序值）倒序 |
| `com.sogou.expressionplugin.expression.manager.f` | `Q0()` 返回内置包清单 |
| `...widget.NoScrollViewPager` | `slide` 字段控制能否横向滑 |

版本更新后类名可能变，用 `dexdump` 找 `emojipackage` 字符串的引用点即可重新定位。
