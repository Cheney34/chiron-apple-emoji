# Chiron × Apple Emoji

把 **Apple 风格的彩色 emoji** 装进 Android，以及一套围绕 **Chiron GoRound TC** 的中文字体定制工具链。

本仓库只包含**源码、构建脚本和文档**。字体成品（`.ttf`）、MTZ 主题包、APK 均在本地由脚本生成，不随仓库分发 —— 原因见 [THIRD-PARTY.md](THIRD-PARTY.md)。

> 新版模块（独立仓库）：https://github.com/Cheney34/apple-input-for-sogou — 最新 **v2.1.1**（表情包升到 Emoji 17.0 / iOS 26，3911 条目）。
>
> 搜狗输入法的 Xposed 模块不再在本仓库内演进。新仓库按版本提供选择：
> [v2.1.1](https://github.com/Cheney34/apple-input-for-sogou/releases/tag/v2.1.1)（推荐：Emoji 17.0 素材 + 四渠道皮肤）、
> [v1.8](https://github.com/Cheney34/apple-input-for-sogou/releases/tag/v1.8) / [v1.7](https://github.com/Cheney34/apple-input-for-sogou/releases/tag/v1.7)（旧版表情模块存档）。
> 本仓库 `lsposed-sogou/` 目录保留原样，作为 v1.x 的历史来源，不再更新。

---

## 当前版本

| 组件 | 版本 | 产物 |
|---|---|---|
| 项目 / Release | **6.5**（tag `v6.5`） | — |
| MTZ 主题（免 Root） | 6.5 | `Chiron-Merriweather_v6.5.mtz` / `Chiron-Merriweather_v6.5_AppleEmoji.mtz` |
| 类原生 KSU 模块 | 6.5.1（versionCode 10，id `chiron_apple_emoji`） | `Chiron_KSU_Font_A17_v6.5.1.zip` |
| Magisk 版模块 | 6.2（versionCode 9） | 不在 6.5 发行内，源码仍在 [`magisk-module/`](magisk-module/) |
| 搜狗 LSPosed 模块 | 1.8（versionCode 10） | 本仓库内已冻结；新版见 [apple-input-for-sogou](https://github.com/Cheney34/apple-input-for-sogou) **v2.1.1** |
| emoji 字体资源 | **Emoji 17.0 / iOS 26**（3946 条序列） | 128 ppem 高位图 / 32·45·60 三档真彩 |

改动记录见 [CHANGELOG.md](CHANGELOG.md)。版本号规则：项目、Root、MTZ 共用同一个语义化版本；字体资源单独编号，因为同一个版本号下两条通道的位图档数不同。

## 该装哪个

| 你的情况 | 装什么 | 为什么 |
|---|---|---|
| 没 Root，只想让系统 emoji 变苹果 | **MTZ** | 走主题引擎运行时覆写，可一键切回，覆盖率比模块高 |
| 有 Root（Magisk / KernelSU / APatch） | **Root 模块** | 直接改 `/system/fonts`，最彻底；但 HyperOS 的 EROFS 逻辑分区上可能挂不上，见下文 |
| 搜狗输入法的表情面板也要换 | **+ LSPosed 模块** | 搜狗面板读自己的 `emojipackage` 资源，换字体对它无效 |
| 酷安 / 微博里仍是安卓 emoji | 无解 | 这类 App 自带 emoji2-bundled 渲染器，任何系统级替换都无效 |

⚠️ 两条通道都能用时，**优先 MTZ**：v5.0 时代的实测日志显示，模块在 HyperOS 4.0 上一次都没挂上（overlay 被 EROFS 挡掉），而同一台机器上的 MTZ 是有效的。

---

## 五个子项目

| 目录 | 做什么 | 产物 |
|---|---|---|
| [`emoji-font/`](emoji-font/) | 用 Apple emoji 位图（Emoji 17.0 / iOS 26），构建一份 Android 能直接用的 `NotoColorEmoji.ttf`（CBDT/CBLC，位图档位按通道裁剪） | 字体文件 |
| [`chiron-font/`](chiron-font/) | 把 Chiron GoRound TC 的西文换成 Merriweather，生成可变字体并打包成 MTZ 主题 | `.mtz` |
| [`magisk-module/`](magisk-module/) | KernelSU / Magisk / APatch 模块，把 emoji 字体挂进 `/system/fonts` | 模块 zip |
| [`ksu-module/`](ksu-module/) | 类原生 AOSP 用的字体模块：中文 + 西文合并字体与 Apple emoji 一次性覆盖 `/system/fonts`，不改 system 分区 | 模块 zip |
| [`lsposed-sogou/`](lsposed-sogou/) | LSPosed 模块，把搜狗输入法表情面板整面板替换成 Apple emoji | `.apk` |

---

## 快速开始

先把素材准备好，只需要一次：

```bash
# 6.5 起用 Emoji 17.0（iOS 26 字形）。npm 上的 emoji-datasource-apple 还停在 16.0.0，
# 17.0 只在 iamcal/emoji-data 的 master 里，用仓库自带脚本按提交号抓：
cd emoji-font
python3 fetch17.py          # 产出 img/ 与 emoji-data.json（3946 条 Apple 序列，约 100 MB）
```

`fetch17.py` 里的 `REV` 固定到一个 commit（`e77759c2`），上游再动也不会改变这次构建的输入。
素材命名统一成 `emoji_u1f600.png` / `emoji_u1f1e8_1f1e6.png`（小写、下划线连接码位）。

### 1. 构建 emoji 字体

`build17.py` 用环境变量读参数（不认命令行 flag）：

```bash
cd emoji-font
pip install fonttools pillow

# Root / KSU 通道：三档真彩，约 60 MB（6.4 及以前的出货就是这个规格）
STRIKES=32,45,60 IMGDIR=./img JSONF=./emoji-data.json \
OUT=../build/emoji/NotoColorEmoji-ksu.ttf python3 build17.py

# MTZ 通道：单档 128 ppem 真彩，约 92 MB
STRIKES=128 IMGDIR=./img JSONF=./emoji-data.json \
OUT=../build/emoji/NotoColorEmoji-mtz.ttf python3 build17.py

# 想要全尺寸五档（约 188 MB，root 直替 /system/fonts 时用）：
# STRIKES=32,45,60,82,128 ...
```

`STRIKES` 是唯一需要按通道区分的参数。档位越少，同一个字形在别的字号上被缩放得越多、边缘越软；v6.2 的 MTZ 就是单档写死成了 256 色调色板才发糊。

### 2. 打包 Root 模块

```bash
cd magisk-module
mkdir -p system/fonts
cp ../build/emoji/NotoColorEmoji-root.ttf system/fonts/NotoColorEmoji.ttf
zip -r ../Chiron-Emoji-v6.2-Root.zip . -x '*/.git*' -x 'system/fonts/.gitkeep'
```

刷入后重启。诊断：模块详情页点「执行」，或 `cat /data/adb/chiron_apple_emoji/post-fs.log`。

### 3. 构建 LSPosed 模块

本地构建需要 `libs/XposedBridgeAPI-82.jar`，比较麻烦。**推荐直接让 CI 出包**：仓库 Actions → 「构建 LSPosed 模块」→ Run workflow，产物在 artifact 里。

```bash
cd lsposed-sogou
python3 tools/make_payload.py --src ./img --out assets/payload.zip --version 17.0
./build.sh
```

装好后在 LSPosed 里勾选「搜狗输入法」，重启输入法进程。

### 4. 生成 MTZ 主题

```bash
cd chiron-font
python3 build_v6.py \
    --src-font ../build/mtz/fonts/Roboto-Regular.ttf \
    --emoji    ../build/emoji/NotoColorEmoji-mtz.ttf \
    --version  6.5 \
    --out      ../Chiron-Merriweather_v6.5_AppleEmoji.mtz
```

脚本打包前会先验三个必过项，不过就直接退出（不会给你一个「能装但难看」的包）：

1. emoji 位图是 **RGBA 真彩**（256 色调色板会被拒）
2. **advance width = 2400 / upem 2048**，否则图形只占格子 80%，看起来偏小、间距偏大
3. 正文字体 **hhea.ascent = 1078**，否则状态栏电量数字下沉约 3px

### 5. 只换 emoji、不动正文（小版本用这条）

6.5 这种做法只换了 emoji 字体，正文与预览图必须逐字节保持不变，所以不重跑 `build_v6.py`，
而是把新字体塞回上一版成品：

```bash
python3 tools/repack_emoji.py \
    --base  ../chiron-v6.4/Chiron-Merriweather_v6.4_AppleEmoji.mtz \
    --emoji ../build/emoji/NotoColorEmoji-mtz.ttf \
    --kind  mtz --version 6.5 \
    --out   ../Chiron-Merriweather_v6.5_AppleEmoji.mtz
```

脚本沿用原包所有 `ZipInfo`（压缩方式、权限位、时间戳），只替换 `fonts/NotoColorEmoji.ttf`
并改写版本串 —— KSU 包丢 755 权限、MTZ 里正文字体被重压缩导致 sha256 变掉，这两个坑都在这里堵住。

完整的构建与发版流程见 [docs/构建与发版.md](docs/构建与发版.md)。

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

- [构建与发版](docs/构建与发版.md) — 从源码到三个产物，以及发版前自查清单
- [变更记录](CHANGELOG.md) — 每个版本改了什么、哪些已知问题还没做
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
