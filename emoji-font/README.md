# emoji-font

把 Apple 彩色 emoji 位图打包成 Android 能直接用的 `NotoColorEmoji.ttf`。

Android 的 emoji 字体是 **CBDT/CBLC（嵌入 PNG 位图）**，不是 COLRv1 矢量。
字体里没有轮廓，`glyf` 表全是空壳，真正显示的是嵌进去的 PNG。
组合 emoji（👨‍👩‍👧、🇨🇳、👍🏽）靠 `GSUB` 的 `ccmp` 连字规则拼出来。

**当前数据：Emoji 17.0 / iOS 26 字形** —— 3946 条 Apple 序列（含肤色与 ZWJ 组合），
比 16.0 多 138 条。新增的 7 个基字符是 🫪 变形脸、🫯 打斗云团、🫈 毛怪、🫍 虎鲸、
🛘 山体滑坡、🪊 长号、🪎 宝箱（对应码位 U+1FAEA / U+1FAEF / U+1FAC8 / U+1FACD /
U+1F6D8 / U+1FA8A / U+1FA8E）。

## 构建

```bash
pip install fonttools pillow

python3 fetch17.py                            # 抓 Emoji 17.0 位图 + emoji-data.json（约 100 MB）
export IMGDIR=./img                           # fetch17 的产物目录
export JSONF=./emoji-data.json
export OUT=./NotoColorEmoji.ttf
export STRIKES=32,45,60                       # 见下表，按通道选
python3 build17.py
```

`IMGDIR` 里的文件名规则是 `emoji_u1f600.png`、`emoji_u1f1e8_1f1e6.png`（小写、下划线连接码位）。
`fetch17.py` 已经把上游 `img-apple-160/` 的 `1f600.png` 重命名成这个格式；手工准备素材时
`emoji-datasource-apple` 的 `img/apple/64`、`img/apple/160` 目录也能直接用，脚本会自己缩放。

`fetch17.py` 把上游固定到 commit `e77759c2`：npm 上的 `emoji-datasource-apple` 停在 16.0.0，
没有 17.0 的图，所以这条链路走的是 `iamcal/emoji-data` 的仓库快照，下游构建才可复现。

## 关键参数

| 常量 | 值 | 说明 |
|---|---|---|
| `UPM` | 2048 | 每 em 单位数 |
| `ADV` | 2400 | 字宽 1.172 em。**必须和原厂一致**，否则 emoji 和汉字混排时右边会多出空隙 |
| `STRIKES` | 按通道选 | 每档一个 ppem，位图边长 = ppem × 1.172。出货规格见下 |

出货规格（6.5）：

| 通道 | `STRIKES` | 字体大小 | 为什么 |
|---|---|---|---|
| MTZ（`..._AppleEmoji.mtz`） | `128` | 约 92 MB | MTZ 要压体积，128 ppem（150 px 位图）单档在聊天字号下够清楚 |
| KSU / Magisk（`/system/fonts`） | `32,45,60` | 约 60 MB | 系统会对齐到最近档，三档覆盖正文到小标题 |
| 想更锐（自用） | `32,45,60,82,128` | 约 188 MB | 官方 Noto Color Emoji 同款做法，任何字号都命中位图 |

## 为什么强调真彩

早期版本为了压体积只留 128 一档、并把 PNG 量化成 256 色调色板，结果：

- Apple 脸部的径向渐变从 6231 色掉到 131 色，出现一圈圈色阶，肉眼可见“发脏”；
- 32sp 下把 128px 缩到 32px，边缘糊；
- 单档位图意味着 FreeType 每次都要重采样，性能也差。

现在一律真彩 PNG32（RGBA8），只是档位按通道裁剪。

## 其它脚本

| 脚本 | 用途 |
|---|---|
| `fetch17.py` | 抓 Emoji 17.0 位图与元数据（固定上游 commit），当前出货用的就是它 |
| `build17.py` | 当前构建脚本（v5 算法：真彩、多档、`ccmp` 连字） |
| `build16.py` | 上一代构建（4 档），保留作对比 |
| `build_emoji.py` | 最早的单档版本 |
| `fetch.py` / `fetch16.py` | 早期从 emoji-datasource 抓素材的脚本（16.0 时代） |
| `verify16.py` | 校验产物：cmap 覆盖、连字条数、位图档位 |

## 已知问题

- **`GSUB` 标签**：本脚本写 `ccmp`，与官方 Noto 一致。若产物出现组合 emoji 散架，先用 `verify16.py` 确认连字规则数，再查渲染端是否做了 shaping。
- **新表情在 App 里点不出来**：字体里已有 17.0 的码位（cmap 1452 个基字符、4006 个字形、3730 条连字），但搜狗等 App 的表情面板读的是自己的白名单，面板里没有的条目只能靠复制粘贴。系统层（微信、短信、备忘录）不受影响。

