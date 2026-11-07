# 变更记录

版本号规则：项目、Root 模块、MTZ 主题共用同一个语义化版本号；emoji 字体资源单独编号（`Emoji-R6-HD` / `Emoji-R6-Compact`），因为同一发行版本下两条通道的位图档数本来就不同。

---

## 6.6 — 2026-11-07 — emoji 位图从 3 档补回 5 档，修「大字号掉回安卓字形」

6.5.2 把挂载链路全部修好了，但用户装上看到的仍然是安卓那张扁平脸。真凶不在挂载，
在**字体本身少了两个档位**。

CBDT/CBLC 是**定点位图**字体。系统按实际渲染的像素大小去挑 strike：

- 6.3 起为了把包体压到 57 MB，`STRIKES` 设成了 `32,45,60`（位图 38/53/70 px）；
- 5.0 那版是 `32,45,60,82,128`（位图 38/53/70/96/150 px）。

小字号落在 38/53/70 里，正常显示 Apple 字形；一旦界面把 emoji 放大到 96 px 或 150 px
（emoji 键盘预览、表情详情、通知大图标、微信大表情、部分 App 的自绘标题），字体里没有
对应档位，FreeType 返回 size 不匹配，Minikin 判定「这个字体画不出这个字号」，**整段回退
到系统自带的 NotoColorEmoji** —— 也就是 AOSP 风格。

所以症状一直很迷惑：小字号像 iOS、一放大就变安卓；有的 App 对、有的 App 不对；
`mount` 看是全挂上了，`stat` 也显示 60 MB 是模块的字体，但画面就是不对。

### 改了什么

- **`system/fonts/NotoColorEmoji.ttf` 重新构建**：`STRIKES=32,45,60,82,128`，
  5 档真彩 RGBA，位图 38/53/70/96/150 px，参数（`bitDepth=32` / `flags=1` /
  `hori.ascender` / `descender` / `widthMax`）与 5.0 逐项对齐。体积 189.7 MiB。
- 字形数 4006（5.0 是 3842），连字 3730 条，含 Unicode 17.0 全部新增表情。
- **`customize.sh` 加档位自检**：安装时若字体小于 130 MB，直接警告「这是 6.3–6.5.2 的
  三档包，大字号会掉回安卓字形」。
- **`scripts/diag.sh` 加档位判定**：「执行」按钮输出的诊断里会写明当前是 5 档还是 3 档。
- **`customize.sh` 自动清掉 `chiron_ksu_font`**：6.3–6.5 用的临时 id 和 `chiron_apple_emoji`
  id 不同，KSU 当两个独立模块并存；挂载按目录名字母序、后挂覆盖先挂，`chiron_ksu_font`
  排在后面，会把本模块的字体顶掉。同项目的临时 id，安装时直接删。
- 挂载链路（`post-fs-data.sh` / `service.sh` / `system.prop` / `action.sh`）与 6.5.2 相同，
  没有改动 —— 那部分是对的。
- 正文字体没动：`Roboto-Regular.ttf` `dcc31ca9…`（69,340,020 B）。

包体从 92.7 MB 涨到 226.2 MiB，多出来的 130 MB 全是 96 px 与 150 px 两档位图。
这是这个方案必须付的成本，5.0 那版也是这个体积。

---

## 6.5.2 — 2026-11-07 — 恢复 bind mount，修「emoji 变回安卓风格」

6.5 / 6.5.1 只靠模块自带的 `system/fonts/` 目录（overlay）。本机 Android 17 实测 overlay
不保证生效：`/system/fonts/NotoColorEmoji.ttf` 仍是系统原版。于是 emoji 能显示（系统自带
Noto 也有 17.0 的码位），但画出来是安卓风格。回退点是 6.3 —— 重写模块时把 5.0 的四道保险删了。

### 改了什么

- **`post-fs-data.sh` 重写**：`mount --bind` 到 `/system/fonts`、`/product/fonts`、
  `/system_ext/fonts` 下每一个 `*Emoji*.ttf`，并 `chcon u:object_r:system_file:s0`；
  全部失败时退化到 overlayfs（挂完立刻验证基础字体可读，读不到就回滚）。
  正文字体与 `font_fallback.xml` 在「实际字节数与模块内不一致」时也一并 bind。
- **`customize.sh` 增加文件名解析**：从 `fonts.xml` / `font_fallback.xml` 的 `und-Zsye`
  家族里提取系统真正引用的 emoji 文件名（`NotoColorEmoji` / `NotoColorEmojiLegacy` /
  `NotoColorEmojiFlags` / `MiSansEmoji`），按 `system` / `product` / `system_ext` / `vendor`
  分区映射到模块内，逐个硬链接一份。只放一个 `NotoColorEmoji.ttf` 会漏。
- **新增 `system.prop`**：`ro.com.google.gmscore.font_provider.disabled=1`，断掉 GMS 往
  `/data/fonts` 下发字体（那份优先级高于 `/system/fonts`）。
- **新增 `service.sh`**：开机完成后清 `/data/fonts`、替换主题字体目录里的 emoji、禁用 GMS
  `FontsProvider` 与 `UpdateSchedulerService`、清 `font_*.dat` 字形缓存，最后补挂一次。
- **新增 `action.sh` + `scripts/diag.sh`**：模块详情页「执行」按钮现场挂载并输出诊断，
  同时写 `/sdcard/emoji_diag.txt`。
- **安装期清 `disable`**：用同 id 升级时 `disable` 标记会保留，装了却仍是禁用状态 —— 另一种
  「装了跟没装一样」。现在安装时自动清掉并打印。
- `uninstall.sh` 清 `/data/adb/chiron_apple_emoji` 状态目录。

### 字体没有任何变化

`Roboto-Regular.ttf` `dcc31ca9…`（69,340,020 B），`NotoColorEmoji.ttf` `9bacf7c3…`
（60,277,864 B），与 6.5 / 6.5.1 逐字节相同。

---

## 6.5.1 — 2026-11-07 — 模块 id 回到 chiron_apple_emoji，不再另起一条

6.5 的包是 6.4 换 emoji 换出来的，能装能用，但模块身份在 6.3 那次改错了：6.3 起用了新 id
`chiron_ksu_font`，于是从 5.0 / 6.2 一路装上来的人，KSU 列表里会**多出一条**。两条都往
`/system/fonts` 放 `NotoColorEmoji.ttf`，谁生效取决于目录名排序，不看版本号。表现就是
「替换成功了、位置也占了，但图是空的」—— 旧模块那份 16.0 字体赢了。

### 改了什么

- `module.prop` 回到 `id=chiron_apple_emoji`（5.x / 6.2 那条线），`versionCode` 10（5.0 是 5，6.2 是 9），
  装上去是**升级覆盖**，不会并列。
- 正文与 emoji 仍在同一个包里（沿用 6.3 起的一体包，不拆回 emoji-only）。
- `customize.sh` 增加冲突检测：安装时扫 `/data/adb/modules/*/module.prop`，谁也在提供
  `NotoColorEmoji.ttf` 或 `Roboto*.ttf`，就在安装界面点名打印 id / 版本 / 名字，并说明
  「后挂载的覆盖先挂载的」。只报告，不替用户禁用别人的模块。检测到 `chiron_ksu_font` 时额外提示卸载。
- `post-fs-data.sh` 日志头从 `chiron_ksu_font` 改为 `chiron_apple_emoji`。
- `ksu-module/README.md` 补「从 6.3–6.5 迁回来」一节；`ksu-module/module.prop` 与出货包对齐
  （6.5 之前这里还停在 `v6.3_refix` / versionCode 6，照仓库构建出不来 6.5）。

### 字体没有任何变化

`Roboto-Regular.ttf` 仍是 `dcc31ca9…`（69,340,020 B），`NotoColorEmoji.ttf` 仍是 `9bacf7c3…`
（60,277,864 B）。6.5.1 只改装法，字形与 6.5 逐字节相同。

### 从 6.3 / 6.4 / 6.5 过来

装 6.5.1 → 到模块列表卸载 `Chiron × Apple Emoji（类原生）`（id `chiron_ksu_font`）→ 重启。

---

## 6.5 — 2026-11-07 — 表情库升到 Emoji 17.0（iOS 26 字形）

正文一个字没动，只换 emoji：`fonts/NotoColorEmoji.ttf` 从 Emoji 16.0 换到 **17.0**。

### 新了什么

Unicode 17.0 / Emoji 17.0 于 2025-09 定稿，共 163 项（7 个基字符 + 芭蕾舞者 + 6 个老表情的
肤色变体 + 150 条 ZWJ 序列）。本版把 Apple 的 iOS 26 版本图画全部收进字体：

| 码位 | 表情 | 名称 |
|---|---|---|
| U+1FAEA | 🫪 | 变形的脸 / distorted face |
| U+1FAEF | 🫯 | 打斗云团 / fight cloud |
| U+1FAC8 | 🫈 | 毛怪 / hairy creature |
| U+1FACD | 🫍 | 虎鲸 / orca |
| U+1F6D8 | 🛘 | 山体滑坡 / landslide |
| U+1FA8A | 🪊 | 长号 / trombone |
| U+1FA8E | 🪎 | 宝箱 / treasure chest |
| U+1F9D1 U+200D U+1FA70 | 🧑‍🩰 | 芭蕾舞者（含 5 档肤色） |

`👯` 戴兔耳朵的人 / `🤼` 摔跤选手 及其男女版本，17.0 才补上肤色，本版一并收进字体。
Emoji 17.0 定稿时去掉了 U+1FADD 苹果核，所以清单里没有它 —— 上游 `iamcal/emoji-data`
的 17.0 集合同样没有，两边一致。

### 数字

| 项 | 6.4（Emoji 16.0） | 6.5（Emoji 17.0） |
|---|---|---|
| Apple 序列数 | 3808 | **3946**（+138） |
| 字形数 | 3842 | **4006** |
| cmap 基字符 | 1445 | **1452** |
| `GSUB` 连字 | 3553 | **3730** |
| MTZ 内 emoji 字体 | 87.8 MB | **92.4 MB** |
| KSU 内 emoji 字体 | 57.1 MB | **60.3 MB** |

### 位图从哪来

npm 的 `emoji-datasource-apple` 停在 16.0.0，没有 17.0 的图。改从 `iamcal/emoji-data`
的 master 取，并固定到 commit `e77759c2`：其 `img-apple-160/1faea.png` 与 Emojipedia
的 `em-content.zobj.net/source/apple/453/…`（iOS 26.4 测试版美术）**逐像素一致**，
所以这套图确实是苹果 iOS 26 的版本画，不是第三方仿画。

`emoji-font/fetch17.py`（新增）把这条链路固化：流式解 tarball 只取 `img-apple-160/`，
约 100 MB，不再需要 npm 包。

### 没动的

- **正文三渠道仍同一份**：`Roboto-Regular.ttf` 69,340,020 B，sha256 `dcc31ca9…`，
  与 6.4 完全一致。
- **MTZ 里的预览图、`description.xml` 布局、KSU 的安装脚本**逐字节保留；
  只改版本串与 emoji 字体本身。
- 位图档位沿用 6.4 的规格：MTZ 单档 128 ppem、KSU `32,45,60` 三档真彩。
  **没有**为了让新表情更清楚而偷偷改档位——那会让体积和上一版不可比。

### 新增工具

- **`tools/repack_emoji.py`**：只替换成品包里的 emoji 字体，其余条目沿用原 `ZipInfo`
  （压缩方式、权限位、时间戳）。KSU 丢 755、MTZ 正文字体被重压缩这两个坑在这里堵住。
- **`emoji-font/fetch17.py`**：抓 17.0 位图与元数据，上游固定 commit。
- `emoji-font/build17.py`：字体名字表版本串改 `Apple17.0v5`；`emoji.fea` 中间文件改为
  写在脚本同目录（原来硬编码 `/root/work/`，换机器就崩）。

### 配套

搜狗输入法表情面板的接管模块在 [apple-input-for-sogou](https://github.com/Cheney34/apple-input-for-sogou)，
本版同步发 **v2.1.1**：`info.xml` 补 8 条新条目、给 6 个老表情打开肤色，payload 从
3868 → 3911 条目（2075 个表情位图 + 肤色变体，源图换成 17.0）。

---

## 6.4 — 2026-11-06 — 私用区 U+F8FF 换成苹果 logo

只动一个字形，其余与 6.3_refix 逐像素一致。

U+F8FF 是苹果系统里唯一的私用区码位（`U+E000–U+F8FF` 里苹果只用了这一个），
iOS / macOS 上打出来是苹果标志。Chiron GoRound TC 原字体在这个码位放的是一颗带字母 N
的五角星，于是换上这套字体后，从备忘录、Pages、Keynote 复制过来的标志会变成星号。

### 改了什么

- **`chiron-font/patch_apple_logo.py`（新增）**：从 `PingFangSC-Regular.ttf` 取 U+F8FF 的轮廓，
  写进 Chiron VF 的同名字形 `uniF8FF`。两者 upem 都是 1000，不用缩放；字宽 658 → 1000
  （苹果原版是占满全角的图标位），`gvar` 里该字形本来就没有 delta，删掉后全档同一形状。
- **三份产物同步换字体**：`Chiron-Merriweather_v6.4.mtz`、`..._AppleEmoji.mtz`、
  `Chiron_KSU_Font_A17_v6.4.zip` 内的 `Roboto-Regular.ttf` 是同一个文件
  （69,340,020 B，sha256 `dcc31ca9…`）。6.3 三个渠道各有各的构建，这次统一。
- **KSU 模块 `versionCode` 6 → 7**，`module.prop` / `README.md` 版本与改动说明同步。
- **`docs/release-notes.md` 换成 6.4 版**。这个文件是 CI 的 `body_path`：打 tag 时
  `softprops/action-gh-release` 会拿它覆盖 Release 正文。它停在 6.2 是 6.3_refix 那次
  「Release 正文写着 v6.2 附件表」的原因，现在补上。

### 验证

- cmap 46,046 码位 / 50,551 字形 / hhea 1078 -348 / typo 976 -246 200 / `wght` 150–700 全部未变；
- 28 / 44 / 76 px × 150 / 330 / 500 / 700 四档字重渲染中英混排样本，与 6.3 差异像素数 0；
- 三个 zip 均 `testzip()` 通过，KSU 包保留 `update-binary` / `customize.sh` / `post-fs-data.sh` /
  `uninstall.sh` 的可执行位。

### 保持

6.3_refix 的星号重画（388×366、中心 531、adv 452）、`@` 上移、行高 1.280 em 全部沿用。

---

## 6.2 — 2026-10-31 — 首个正式版

项目第一次对外发布：MTZ 主题首次带上 Apple Color Emoji，Root 模块脚本重写，搜狗 LSPosed 模块一并出 1.7。这一版的重点是把规格问题挡在构建入口 —— 256 色单档、advance 2550 的旧字体从此打不进 MTZ。

### 新增与修正

- **对外只报一个版本号 6.2**（审计 P1-9）。此前 Root 模块是 `v5.0`/`v5.1`、MTZ 是 `6.2`、搜狗模块是 `1.7`，同一个「Apple Emoji」名义下装着质量差 10 倍的两种字体，用户无从分辨。现在 `module.prop`（versionCode 9）、MTZ 文件名、`description.xml` 三处一致。
- **`chiron-font/build_v6.py` 重写，加入发行前校验**。打包前用 fontTools 读一遍 emoji 字体，任一项不过就 `exit 1`（审计 P0-1、P0-2、P1-7、P1-8）：
  - 位图档数 ≥ 2（单档会在缩放时发虚）
  - 位图 PNG color type = 6（RGBA 真彩；256 色调色板直接拒绝）
  - `advance width = 2400 / upem 2048`（否则图形只占格子 80%，看起来偏小、间距偏大）
  - `cmap` 码位数 ≥ 1440、GSUB 含 `ccmp`
  - 正文字体 `hhea.ascent = 1078`（低了说明没跑过 `fix_metrics.py`，电量数字会下沉 3px）
- **`description.xml` 结构补齐**（P1-10）：`<version>` 与文件名同步，补 `<titles>` / `<authors>` / `<designers>` / `<descriptions>` 四个 locale 块，`title` 从 `Chiron Merriweather` 改为 `Chiron Emoji`，与项目名一致。
- **根节点仍保留 `<MIUI-Theme>`，不改 `<theme>`**。审计报告建议改（两份参照包用的是 `<theme>`），但 v6.2 用 `<MIUI-Theme>` 在真机上已经装得上、跑得动。改错的后果是「装不上」，而收益只是「更符合规范」——在没有备用测试机可反复刷的情况下，这个交换不划算，先记在已知问题里。
- **`emoji-font/build17.py` 的 `STRIKES` 支持环境变量覆盖**。MTZ 通道可以出双档真彩（`STRIKES=45,96`，约 55–60 MB），不再复用历史遗留的单档量化字体；Root 通道默认五档不变。
- **README 修正**：原文写 `build17.py --src ... --out ...`，但脚本只认 `IMGDIR` / `JSONF` / `OUT` 环境变量，照着文档敲必然报错。已改为可执行的写法，并补了「当前版本」与「该装哪个」两张表。

### 保持

5.1 的全部安全修复（见下），以及搜狗 LSPosed 模块 1.7。

### 附件说明

本次 Release 附带的 MTZ 与 Root 模块是**实机验证过的历史构建**，与上面的源码改动不是同一次产出：

| 附件 | 版本 | 与源码的差异 |
|---|---|---|
| `Chiron-Merriweather_v6.2_AppleEmoji.mtz` | 6.2 | 内含 emoji 位图仍是 256 色量化 + 单档 128px，advance width 2550（1.245 em）未归一，cmap 少 12 个码位 → 发糊、偏小、间距偏大 |
| `AppleEmoji_Chiron_v5.0_hd.zip` | 5.0 | 缺 `uninstall.sh`，覆盖主题 emoji 前不备份，overlayfs 兜底默认开启（这三项 5.1 起才改） |

APK（搜狗 LSPosed 1.7）由 CI 从源码构建，与源码一致。

### 已知未做

| 项 | 原因 |
|---|---|
| MTZ 包内没有授权声明 | 主题引擎对 `fonts/`、`preview/` 之外的条目容忍度未验证，往 zip 里塞 NOTICE 有装不上的风险（审计 §8 C-2）。授权说明只放在仓库与 Release 正文里 |
| `pm disable` 仍会连带关掉 Google 字体下载 | 影响面比 P0 版本小（可卸载还原），但要彻底解决需要改成只清 `/data/fonts` 不 disable，留待实测 |
| Root 模块在 HyperOS 的 EROFS 分区仍可能挂不上 | 平台限制，`post-fs-data.sh` 已把失败路径写成「不生效但不影响开机」 |

---

## 5.1 — 2026-10-31

安全修复，对应审计报告 P0-3 / P0-4 / P0-5 / P0-6 与 P1-11。**只改脚本，不动字体二进制。**

- **不再无备份删除**：`customize.sh` 里 `rm -rf /data/fonts` 改为整目录 `mv` 进 `/data/adb/chiron_apple_emoji/backup/install-<时间>/`；主题目录里的 emoji 字体先 `cp -p` 备份、**备份成功才覆盖**。每笔写进 `backup/journal.txt`。`post-fs-data.sh`、`action.sh` 里同样的删除一并改成 stash。
- **`pm disable` 可逆**：`service.sh` 每禁一项记一行 `user=<uid> <组件>` 到 `disabled.list`（`grep -qxF` 去重，只记真正成功的）。
- **新增 `uninstall.sh`**：按清单逐个 `pm enable`，还原主题字体与 `/data/fonts`，卸载 bind mount / overlay，清单改名 `.done`。
- **overlayfs 回退收紧**：默认关闭，需 `touch /data/adb/chiron_apple_emoji/enable_overlay` 才尝试；加开机死循环熔断（`overlay_tried` 无对应 `overlay_confirmed` 则永久停用）；探测条件从「文件非空」升级为「基础字体可读 + `/system/fonts/*.ttf` 数量 ≥5 + emoji 已是本模块那份」，任一不满足立即 `umount -l`。
- **新增 `NOTICE.txt`**，随包分发，说明位图版权归 Apple、未获再分发授权、仅限个人本机使用、卸载还原范围。
- **`update-binary` 探测安装器**：按 `/data/adb/{magisk,ksu,ap}/util_functions.sh` 顺序找，找不到或没有 `install_module()` 就明确报错 `exit 1`，不再静默 `exit 0`（此前 APatch 下表现为「装了但什么都没装」）。
- `scripts/diag.sh` 新增「可还原性」一节，打印备份目录、`disabled.list`、三个 overlay 标记。

---

## 5.0 — 2026-10-29

Root 模块改真彩。v4 为压体积把位图 `quantize(256)`，Apple 脸部的径向渐变从 6231 色掉到 131 色，出现一圈圈色阶；v5 改回真彩 PNG32，与 Noto 官方同规格。5 档位图 38/53/70/96/150px，GSUB 连字 3553 条。

---

## 1.7 — 2026-10-30

搜狗 LSPosed 模块：不再靠排序值「挪走」内置分组，改为在 `File.list()` 与 `ExpressionUtil.u()` 两处拦截，真正移除「组合」「拼装」两个分组，卸载即恢复。
