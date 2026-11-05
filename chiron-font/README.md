# chiron-font

把 **Chiron GoRound TC** 的西文字母和数字换成 **Merriweather**，保留中文骨架，
输出 MIUI / HyperOS 的 `.mtz` 主题包。

顺带解决了一个很隐蔽的坑：**Chiron 原厂的垂直度量偏上，导致状态栏电量数字下沉**。

## 构建链

```
Chiron GoRound TC VF（中文 + 西文）
        │
        ├─ 提取中文轮廓 ─────────────┐
        ├─ Merriweather VF 补西文 ──┤
        │                           ▼
        └──────────────────▶ 合成可变字体 Roboto-Regular.ttf
                                    │
                                    ├─ 修正垂直度量
                                    └─ 打包 fonts/ + preview/ + description.xml → .mtz
```

| 脚本 | 做什么 |
|---|---|
| `build_chiron.py` | 主合成：中文字形取自 Chiron，西文与数字取自 Merriweather |
| `build_misans_vf.py` | 另一条路线：西文用 MiSans 的数字变体 |
| `build_v4.py` / `build_v5.py` | 加入 emoji 并打包 MTZ（v5 = 真彩 emoji） |
| `build_v6.py` | 最终版本，含 Apple Emoji 与预览图生成 |
| `fix_metrics.py` | 后处理：把下面那三套垂直度量改成一致 |
| `fix_glyphs.py` | 后处理：修 `@` 下沉与 `*` 过大 |

流水线顺序：合成 → `fix_metrics.py` → `fix_glyphs.py`。

脚本里的路径是绝对路径（`/root/work/...`），迁移到别的机器要改文件顶部的常量：
`SRC_FONT`、`EMOJI`、`STAGE`、`OUT`。

## 垂直度量：为什么电量数字会下沉

Android 的 `TextView` 单行垂直居中，基线位置是：

```
baseline = -(top + bottom) / 2 - top
```

其中（**注意 `top` 是负数**）：

```
top    = min(-hhea.ascent, -OS/2.usWinAscent)
bottom = max( hhea.descent,  OS/2.usWinDescent)
```

字框中心 = `(top + bottom) / 2`。如果字体的 `ascent` 特别大，字框中心就会被顶高，
而数字本身还待在原来的位置 —— 结果就是**数字在框里偏下**。

实测三份字体（单位：1/1000 em）：

| | hhea ascent / descent | 字框中心 | 数字中心 | 数字相对字框 |
|---|---|---|---|---|
| MiSans 原生 | 1044 / -282 | 381.0 | 372.5 | **-8.5** |
| Chiron 原厂 | 1138 / -288 | 425.0 | 356.0 | **-69.0** |
| 修正后 | 1078 / -348 | 365.0 | 356.0 | **-9.0** |

Chiron 的 `ascent` 是 1.138 em，比 MiSans 的 1.044 em 大 0.094 em，字框中心被顶高 44 单位；
加上数字自身中心低 16.5，合计 60.5 单位 = 0.06 em。

状态栏电量文字约 10–12sp，2.75 倍屏下是 28–33 px —— **下沉 1.7–2 px**。
字本身才 28 px 高，那是一眼能看出来的位移。这也解释了为什么只有电池明显：
它是最小的居中容器，比例误差被放得最大。

### 修正

**行高总和保持不变**，只挪分配：

```
hhea.ascent   1138 → 1078      hhea.descent   -288 → -348    （总和 1426 不变）
OS/2.usWinAscent 1138 → 1078   usWinDescent    288 →  348
OS/2.sTypoAscender 1013 → 976  sTypoDescender -209 → -246  （lineGap 200 不变）
```

三套度量**必须一起改**。只改 `hhea` 没有用，因为 `top` 取的是
`min(-hhea.ascent, -usWinAscent)`，`usWinAscent` 还是 1138 就把结果锁死了 ——
这是第一版修正“只改善了一点点”的原因。

改完复测：数字在控件里的偏移 **-69.0 → -9.0**，与 MiSans 原生的 -8.5 基本重合。
因为行高总和不变，中文行距、多行排版、列表高度全都不受影响。

## MTZ 结构

```
description.xml     主题信息
fonts/
    Roboto-Regular.ttf
preview/
    preview_fonts_0.jpg   主题商店预览图
```

`description.xml` 的根节点用 `<MIUI-Theme>`，需要 `title / author / designer / version /
uiVersion / fontWeight / description` 几个字段。`fontWeight` 列出可变字体的字重轴档位，
必须是逗号分隔的整数。

## 已知问题

- **只改 hhea 不够**：见上，三套度量要同步。
- **`Roboto-Regular.ttf` 是个可变字体**，MIUI 按 `fvar` 的 `wght` 轴实例化。轴范围要和
  `fontWeight` 字段对得上，否则系统取不到某个字重时会回退到默认值。
- **emoji 不进主字体**：emoji 单独一份 `NotoColorEmoji.ttf` 放在 `fonts/` 下，
  由系统按 `und-Zsye` 语言标签 fallback。

## 垂直度量修正（v5.2 起必跑）

`fix_metrics.py` 把 hhea / OS2.typo / OS2.win 三套度量对齐到同一行框中心，
修掉「状态栏电池数字下沉」。**只改度量，不动字形，行高总和保持 1.426 em。**

```bash
python3 fix_metrics.py 输入.ttf 输出.ttf          # 改并写出
python3 fix_metrics.py 输入.ttf --report          # 只看现状
```

会打印这样的对照：

```
=== 修正前 ===
  32px 字 / 39px 框：顶留白  10.0px  底留白   5.6px  偏差 +2.2px
=== 修正后 ===
  32px 字 / 39px 框：顶留白   8.1px  底留白   7.5px  偏差 +0.3px
```

一个容易踩的坑：**只改 hhea 没用**。Android 算 `top` 时取
`min(hhea.ascent, -usWinAscent)`，`usWinAscent` 不动，`top` 就被它锁死，
算出来的基线和没改一样（v5.1 就是这么翻车的）。

## 标点修正（v5.3 起必跑）

`build_v5.py` 把 0x21–0x7E 整段 ASCII 交给 Merriweather，其中两个字符在中文界面里露馅：

| 字符 | 现象 | 数据 |
|---|---|---|
| `@` U+0040 | 「@昵称」时比中文低一截 | Merriweather 的 @ 中心 0.243 em，Chiron 中文字框中心 0.370 em，差 0.127 em |
| `*` U+002A | 拨号盘上比数字还大一圈 | 高 0.492 em vs Roboto 的 0.414 em；**更关键的是形状完全不同** |

### 星号不是「大了一点」，是形状不对

两版星号的轮廓结构就不一样：

| | 轮廓 | 点数 | 包围盒 | 墨面积 | 说明 |
|---|---|---|---|---|---|
| Merriweather | 1 个 | 30 点全直线 | 473 × 492 | **1.24 em²** | 六条从中心放射的短杠，像「米」字 |
| Chiron | 1 个 | 130 点全曲线 | 391 × 356 | **0.87 em²** | 三根圆头细杠交叠，整片实心 |
| Roboto 原版 | 1 个 | 15 点 | 825 × 847（upem 2048）| — | 三杠交叠，与 Chiron 同构 |

Merriweather 那 30 个点全部是 `lineTo`，中心留一个空心交点；Chiron 的 130 个点全是
`qCurveTo`，圆头收笔。**这样的差异缩小救不回来**——按 0.8415 缩完，它在拨号盘上
依然是一片「雪花」，和 `0`、`#` 的笔画语言完全不搭。所以星号直接**换形**，取 Chiron 的。

### 处理方式

- **`@`** 等比缩到 0.920 em 高（Roboto 原版就是这个高度），中心抬到 0.350 em，
  字宽 977 → 926。保留 Merriweather 的衬线造型。
- **`*`** 用 Chiron 的星号（adv 452），整体平移到中心 0.504 em，与 Roboto 对齐。

两个字形都从 Chiron 取轮廓，`gvar` 记录随轮廓一起搬过来（点数、点序与 Chiron 原字一致），
150–700 的可变轴完整。实测三档实例：

```
wght 150   @ 高 910 中心 347   * 宽 378 高 337 中心 513
wght 330   @ 高 920 中心 350   * 宽 391 高 356 中心 504
wght 700   @ 高 942 中心 354   * 宽 405 高 378 中心 494
```

```bash
python3 fix_glyphs.py 原始合并字体.ttf 输出.ttf
```

脚本要求输入是**未经处理**的合并字体。`CHIRON` 常量默认指向
`/root/work/fonts/Roboto-Regular.ttf`（Chiron GoRound TC VF 原件），换机器要改。

**为什么 @ 不用 Chiron 的**：试过。Chiron 的 @ 是一根均匀粗细的圆环，与 Merriweather
的衬线字母并排时明显偏细、偏轻，英文邮箱、代码注释里看着像混进了别的字。
星号恰恰相反——它是纯几何图形，没有衬线细节可丢，换成 Chiron 反而更协调。

**为什么 @ 下沉不是「移植失误」**：Roboto 原版 @ 的中心也是 0.239 em，和 Merriweather
几乎一样。西文字体的 @ 本来就下沉，单看拉丁文本没问题，只有和中文并排时才显得低。
要修的是「与中文的关系」，不是「与拉丁的关系」。
