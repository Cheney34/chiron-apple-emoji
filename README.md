# Chiron × Apple Emoji

把 **Apple 风格的彩色 emoji** 装进 Android，以及一套围绕 **Chiron GoRound TC** 的中文字体定制工具链。

本仓库只包含**源码、构建脚本和文档**。字体成品（`.ttf`）、MTZ 主题包、APK 均在本地由脚本生成，不随仓库分发 —— 原因见 [THIRD-PARTY.md](THIRD-PARTY.md)。

---

## 五个子项目

| 目录 | 做什么 | 产物 |
|---|---|---|
| [`emoji-font/`](emoji-font/) | 用 Apple emoji 位图，构建一份 Android 能直接用的 `NotoColorEmoji.ttf`（CBDT/CBLC，5 档位图） | 字体文件 |
| [`chiron-font/`](chiron-font/) | 把 Chiron GoRound TC 的西文换成 Merriweather，生成可变字体并打包成 MTZ 主题 | `.mtz` |
| [`magisk-module/`](magisk-module/) | KernelSU / Magisk / APatch 模块，把 emoji 字体挂进 `/system/fonts` | 模块 zip |
| [`ksu-module/`](ksu-module/) | 类原生 AOSP 用的字体模块：中文 + 西文合并字体与 Apple emoji 一次性覆盖 `/system/fonts`，不改 system 分区 | 模块 zip |
| [`lsposed-sogou/`](lsposed-sogou/) | LSPosed 模块，把搜狗输入法表情面板整面板替换成 Apple emoji | `.apk` |

---

## 快速开始

### 1. 构建 emoji 字体

```bash
cd emoji-font
pip install fonttools pillow
# 素材：Apple emoji 160px PNG（emoji-datasource-apple 的 img-apple-160 目录）
python3 build17.py --src /path/to/img-apple-160 --out NotoColorEmoji.ttf
```

### 2. 打包 Magisk 模块

```bash
cd magisk-module
cp /path/to/NotoColorEmoji.ttf system/fonts/
zip -r ../AppleEmoji-Chiron.zip . -x '*.git*'
```

刷入后重启。诊断：`/data/local/tmp/emoji_diag.txt`，或直接 `cat /data/adb/modules/*/post-fs.log`。

### 3. 构建 LSPosed 模块

```bash
cd lsposed-sogou
# 先按 libs/README.md 放好 XposedBridgeAPI-82.jar
# payload.zip 含 Apple 位图，需自己生成：
python3 tools/make_payload.py --src /path/to/img-apple-160 --out assets/payload.zip
./build.sh
```

装好后在 LSPosed 里勾选「搜狗输入法」，重启输入法进程。

### 4. 生成 MTZ 主题

```bash
cd chiron-font
python3 build_v6.py   # 需要先准备好 Chiron 源字体和 Merriweather VF
```

---

## LSPosed 模块的工作原理

搜狗的表情面板读的是 `files/sogou/emojipackage/<分组id>_<排序值>/`，每个目录里有：

```
emoji/          20000.png、20001.png …… 表情位图（64×64）
info.xml        该组的表情清单（unified 码位、名称、是否支持肤色）
<group>.png     底部 tab 图标（84×84）
version.json    版本串
```

模块不 root、不删文件，只做两件事：

1. **进程内写文件** —— 模块 App 发广播，搜狗进程里的 Receiver 收到后用自己的 `context.filesDir` 写入，绕开 scoped storage；
2. **改原厂副本前先备份** —— 备份在 `files/sogou/.ios-emoji-backup`，按分组 id 去重，只保留最早的原厂副本，卸载模块可恢复。

另外两个 hook：

- **`NoScrollViewPager.setScrollable`** —— 搜狗用 `showSlideAnimation()` 把面板锁死 900ms 禁止左右滑，hook 后放开，恢复 iOS 那种横向滑动；
- **`File.list()` 过滤 + `ExpressionUtil.u()` 拦截** —— 把搜狗内置的「组合」「拼装」两个分组从列表里摘掉，并阻止它每次启动重新解压。

分组排序值是 `id_order` 里的 `order`，**越大越靠前**。脚本给的 `order` 在 9.0e12 量级，压过搜狗内置包用的 `System.currentTimeMillis()`。

---

## 已知限制

| 限制 | 说明 |
|---|---|
| 搜狗没有 14 键 | 10.32.21 的 `resources.arsc` 里只有九键 / 全键 / 大九键 / 双拼 / 手写 / 笔画。键位映射在 native 拼音引擎 `.so`，Java 侧只传 `keyboardType` 整数，改不了 |
| 部分 emoji 点不动 | 搜狗的表情白名单停在 Unicode 15.0，15.1+ 新增的 36 条（🍋‍🟩 🍄‍🟫 🫩 🪉 🪏 🇨🇶 等）没有词条 |
| 酷安 / 微博 不跟随系统字体 | 这类 App 自带渲染器或自带 emoji 字体，换 `/system/fonts` 无效。详见 [docs/emoji字体通道分析.md](docs/emoji字体通道分析.md) |

---

## 文档

- [emoji 字体在 Android 上的三条通道](docs/emoji字体通道分析.md) — 为什么有的 App 换了字体没反应
- [发行包审计报告](docs/审计报告.md) — 两版 emoji 字体的差异、脚本安全问题

---

## 许可

- 本仓库的**代码**（构建脚本、LSPosed 模块、模块 shell 脚本）：MIT，见 [LICENSE](LICENSE)
- 涉及的第三方字体与美术资源各有其授权，**不可直接再分发**，见 [THIRD-PARTY.md](THIRD-PARTY.md)

## 致谢

- [Chiron GoRound TC](https://github.com/chiron-fonts) — 中文骨架
- [Merriweather](https://github.com/SorkinType/Merriweather) — 西文（SIL OFL 1.1）
- [Noto Emoji](https://github.com/googlefonts/noto-emoji) — 字体工程结构参考
- [250king/SougouEmojiFixer](https://github.com/250king/SougouEmojiFixer) — 搜狗表情面板替换的原始思路
