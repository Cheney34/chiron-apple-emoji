# 第三方资源与授权

本仓库**只分发代码**。所有字体与图片资源都由使用者在本地从合法来源获取，
再用仓库里的脚本处理。这样做既是为了遵守各家授权，也是为了避免公开仓库
变成侵权素材的集散地。

| 资源 | 权利方 | 授权 | 能否再分发 |
|---|---|---|---|
| Apple Color Emoji 位图 | Apple Inc. | **专有**，无公开授权 | ❌ 不可。Apple 的 emoji 美术资源不允许再分发，个人设备上使用属于灰色地带 |
| Chiron GoRound TC | Chiron 字体项目 | 依其官方仓库声明（OFL / 自定义，以原仓库为准） | ⚠️ 需遵守原授权，保留版权声明 |
| Merriweather | Sorkin Type Co. | SIL Open Font License 1.1 | ✅ 可，须保留 OFL 与版权声明，改名后分发 |
| Noto Color Emoji | Google | SIL OFL 1.1（字体） / Apache 2.0（工具） | ✅ 可 |
| 搜狗输入法 | 北京搜狗科技 | 专有 | ❌ 不可。本仓库只做运行时 hook，不修改、不分发其 APK |
| 搜狗表情面板 XML 清单（`lsposed-sogou/manifests/`） | 本项目重新整理 | MIT | ✅ 只是 emoji 码位与名称的结构化数据 |

## 关于 Apple Emoji

Apple 的 emoji 图片是 Apple 的美术作品。即使你手上有 `emoji-datasource-apple`
这类第三方整理包，其中的 PNG 依然来自 Apple 的系统字体。

因此本仓库：

- **不提供** `payload.zip`、`NotoColorEmoji.ttf`、`.mtz`、`.apk` 等含 Apple 位图的产物；
- 提供 `make_payload.py` / `build17.py`，由使用者用自己本地的素材生成。

如果你要公开发布成品，请自行评估风险。这不是技术问题，我不能替你下判断。

## 字体元数据

构建脚本会改写字体的 `name` 表。若分发产物，建议保留原字体的版权字段，
不要声称是自己原创的字体 —— 改度量、换西文属于**衍生**，不是**原创**。
