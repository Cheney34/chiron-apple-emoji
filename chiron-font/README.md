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
