# emoji-font

把 Apple 彩色 emoji 位图打包成 Android 能直接用的 `NotoColorEmoji.ttf`。

Android 的 emoji 字体是 **CBDT/CBLC（嵌入 PNG 位图）**，不是 COLRv1 矢量。
字体里没有轮廓，`glyf` 表全是空壳，真正显示的是嵌进去的 PNG。
组合 emoji（👨‍👩‍👧、🇨🇳、👍🏽）靠 `GSUB` 的 `ccmp` 连字规则拼出来。

## 构建

```bash
pip install fonttools pillow

export IMGDIR=/path/to/img-apple-160        # Apple emoji 160×160 PNG 目录
export JSONF=./emoji-data.json              # 仓库自带，码位与分类数据
export OUT=./NotoColorEmoji.ttf
python3 build17.py
```

`IMGDIR` 里的文件名规则是 `emoji_u1f600.png`、`emoji_u1f1e8_1f1e6.png`（小写、下划线连接码位），
即 `emoji-datasource-apple` 的 `img/apple/160/` 目录。其它尺寸也行，脚本会缩放到目标档位。

## 关键参数

| 常量 | 值 | 说明 |
|---|---|---|
| `UPM` | 2048 | 每 em 单位数 |
| `ADV` | 2400 | 字宽 1.172 em。**必须和原厂一致**，否则 emoji 和汉字混排时右边会多出空隙 |
| `STRIKES` | 32 / 45 / 60 / 82 / 128 | 5 档位图。少一档，某些字号就会用最近档硬缩放，边缘发糊 |

## 为什么是 5 档、真彩

早期版本为了压体积只留 128 一档、并把 PNG 量化成 256 色调色板，结果：

- Apple 脸部的径向渐变从 6231 色掉到 131 色，出现一圈圈色阶，肉眼可见“发脏”；
- 32sp 下把 128px 缩到 32px，边缘糊；
- 单档位图意味着 FreeType 每次都要重采样，性能也差。

现在 5 档真彩 PNG32，字体约 45 MB。这是官方 Noto Color Emoji 的同款做法。

## 其它脚本

| 脚本 | 用途 |
|---|---|
| `build16.py` | 上一代构建（4 档），保留作对比 |
| `build_emoji.py` | 最早的单档版本 |
| `fetch.py` / `fetch16.py` | 从 emoji-datasource 抓取素材与清单 |
| `verify16.py` | 校验产物：cmap 覆盖、连字条数、位图档位 |

## 已知问题

- **`GSUB` 标签**：本脚本写 `ccmp`，与官方 Noto 一致。若产物出现组合 emoji 散架，先用 `verify16.py` 确认连字规则数，再查渲染端是否做了 shaping。
- **Unicode 15.1+ 缺字**：`emoji-data.json` 是 16.0 的清单，但搜狗等 App 的白名单可能停在 15.0，新表情在字体里存在、在 App 里点不出来。这是 App 侧的限制，不是字体问题。
