# Chiron 项目源码索引（2026-11-05）

本包内是当前最新的全部源码，对应出货版本 **v6.5.2**。

## 版本对照

| 源码目录 | 对应出货文件 | 版本 |
|---|---|---|
| `lsposed-sogou/` | `Chiron_Emoji_Sogou_LSPosed_v1.8.apk` | v1.8 |
| `chiron-font/` | `Chiron-Merriweather_v6.5.mtz`<br>`Chiron-Merriweather_v6.5_AppleEmoji.mtz` | v6.5 |
| `ksu-module/` | `Chiron_KSU_Font_A17_v6.5.2.zip` | v6.5.2 |
| `emoji-font/` | 上两个 mtz 与 KSU 包内的 `NotoColorEmoji.ttf` | Emoji 17.0 / iOS 26 |
| `magisk-module/` | 未出货（Magisk 版，审计未过） | — |

## 各目录说明

### lsposed-sogou/ —— 搜狗输入法表情接管模块

```
AndroidManifest.xml     应用清单（含隐藏桌面图标的 activity-alias 开关）
build.sh                可移植构建脚本，自动探测 SDK
src/com/chiron/iosemoji/
  MainActivity.java     界面：分区卡片网格、隐藏图标开关、日志
  EmojiService.java     安装/还原逻辑，按分组解压写入搜狗目录
  Protocol.java         指令常量（install_all / install_core / install_groups / restore）
  Groups.java           10 个分组的 id、名称、张数、图标
  HookEntry.java        LSPosed 入口
  GroupFilterHook.java  表情面板分组过滤
  GestureHook.java      手势相关
res/                    布局、颜色、字符串、分组图标
manifests/              10 个分组的 info.xml（从搜狗原包提取）
tools/make_payload.py   生成 assets/payload.zip 的脚本
signing/debug.keystore  签名（与 v1.5–v1.8 同一份，可覆盖安装）
icons/                  分组图标源图
```

**构建**：把 `XposedBridgeAPI-82.jar` 放进 `libs/`，再准备 `assets/payload.zip`（见 `tools/make_payload.py`，源图约 3800 张，或用出货 APK 内已有的那份），然后

```bash
cd lsposed-sogou && ./build.sh
```

`payload.zip` 未包含在本包内（24 MB，Emoji 17.0 素材，3911 条目），由 `tools/make_payload.py` 从本地素材生成。

### chiron-font/ —— 字体合并与字形修正

```
build_v5.py        纯字体 mtz 打包
build_v6.py        含 Apple emoji 的 mtz 打包
fix_metrics.py     hhea / OS/2 行高度量修正（行高 1.280 em）
fix_glyphs.py      @ 上移、# 放大、* 定尺寸
build_chiron.py    早期 Chiron + 西文合并
build_misans_vf.py 米珊变量字体处理
```

**注意** `fix_glyphs.py` 的星号分支仍是自绘直角星的旧逻辑（`STAR_ARM=335` / `STAR_BAR=34`），与出货版本不一致。出货版 `*` 用的是 Chiron 官方源的原生轮廓，按 335 高等比缩放并搬运 gvar，这一步没回写进脚本。`@` 与 `#` 的处理与出货一致。

### ksu-module/ —— KernelSU 字体模块

```
module.prop         版本 v6.3_refix
customize.sh        安装时改 font_fallback.xml（zh-Hans / zh-Hant 首位插入 9 行）
post-fs-data.sh     挂载 system/fonts 下三个文件
uninstall.sh        卸载还原
META-INF/           刷机脚本
```

字体文件（`system/fonts/*.ttf`，约 200 MB）未包含，来源于 `chiron-font` 的输出与 `emoji-font` 的裁剪结果。

## 环境

- JDK 17+、Android SDK build-tools 34、platform android-34
- Python 3.11 + fontTools / shapely / Pillow / numpy
