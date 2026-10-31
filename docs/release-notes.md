# Chiron Emoji 6.2

第一个正式版本。把 Apple 风格的彩色 emoji 装进 Android，配一套围绕 **Chiron GoRound TC** 的中文字体工具链。

## 下载哪个

| 文件 | 版本 | 给谁 | 怎么装 |
|---|---|---|---|
| `AppleEmoji_Sogou_LSPosed_v1.7.apk` | 1.7 | 搜狗输入法的表情面板也要换 | LSPosed 里勾选「搜狗输入法」，重启输入法进程 |
| `Chiron-Merriweather_v6.2_AppleEmoji.mtz` | 6.2 | 没 Root，只想让系统 emoji 变苹果 | 设置 → 主题 → 字体 → 从本地导入 |
| `AppleEmoji_Chiron_v5.0_hd.zip` | 5.0 | 有 Root（Magisk / KernelSU / APatch） | 用管理器刷入，重启 |

两条通道都能用时**优先 MTZ**：实测日志显示，模块在 HyperOS 4.0 的 EROFS 逻辑分区上可能一次都挂不上，而同一台机器上的 MTZ 是有效的。

## 附件说明（重要）

本页三份附件都是**实机验证过的构建**，与仓库源码不是同一次产出：

| 附件 | 版本 | 与源码的差异 |
|---|---|---|
| `Chiron-Merriweather_v6.2_AppleEmoji.mtz` | 6.2 | 内含 emoji 位图仍是 256 色量化 + 单档 128px，字宽 2550（1.245 em）未归一，cmap 少 12 个码位 → 图形只占格子约 80%，缩放发虚、间距偏大 |
| `AppleEmoji_Chiron_v5.0_hd.zip` | 5.0 | 缺 `uninstall.sh`；覆盖主题 emoji 前不备份；overlayfs 兜底默认开启（这三项 5.1 起才改） |
| `AppleEmoji_Sogou_LSPosed_v1.7.apk` | 1.7 | 由 CI 从源码构建，与源码一致 |

重建后的 MTZ 与 Root 模块会替换本页附件，文件名会带构建日期，届时上表可整段删除。

<!--
附件的校验值（SHA-256 前 12 位），便于核对下载完整性：
  APK  63568b77df0b   25,367,456 B
  MTZ  8d26641266f7   56,377,266 B
  ZIP  fb92a4a68cb1  188,861,610 B
-->

## 这次发布包含什么

- **MTZ 主题首次带上 Apple Color Emoji**，`build_v6.py` 同时生成四张预览图
- **构建入口加校验**：打包前检查位图档数、色彩模式、advance width、cmap 码位数、GSUB `ccmp`、正文字体垂直度量，任一不过直接拒绝出包。旧那种 256 色单档字体从此打不进来
- **`description.xml` 结构补齐**：`<version>` 与文件名同步，补 `titles` / `authors` / `designers` / `descriptions` 四个 locale 块，标题统一为 `Chiron Emoji`
- **Root 模块脚本**：覆盖前先备份、每笔写 journal；新增 `uninstall.sh`，卸载时还原被禁用的 GMS 字体服务与主题目录里的 emoji；overlayfs 兜底改为**默认关闭**、需手动开启，并带开机死循环熔断；安装器自动识别 Magisk / KernelSU / APatch，找不到 `install_module()` 就明确报错而不是静默成功
- **搜狗 LSPosed 模块 1.7**：改为在 `File.list()` 与 `ExpressionUtil.u()` 两处拦截，真正移除内置的「组合」「拼装」分组，卸载即恢复
- **构建脚本可在 Windows 跑**：`build_v6.py` 的路径由硬编码绝对路径改为命令行参数

## 已知限制

| 限制 | 说明 |
|---|---|
| 酷安 / 微博里仍是安卓 emoji | 这类 App 自带 emoji2-bundled 渲染器，任何系统级字体替换都无效，不是本项目的 bug |
| 搜狗没有 14 键 | 键位映射在 native 拼音引擎 `.so` 里，Java 侧改不了 |
| 部分 emoji 点不动 | 搜狗的表情白名单停在 Unicode 15.0，15.1+ 新增的 36 条没有词条 |
| Root 模块在部分 HyperOS 上不生效 | EROFS 逻辑分区会挡掉 overlay；失败路径已写成「不生效但不影响开机」，日志在 `/data/adb/chiron_apple_emoji/post-fs.log` |
| MTZ 包内没有授权声明 | 主题引擎对 `fonts/`、`preview/` 之外条目的容忍度未验证，授权说明只放在仓库与本页 |

## 授权

- 仓库代码（构建脚本、LSPosed 模块、模块 shell 脚本）：MIT，见 [LICENSE](https://github.com/Cheney34/chiron-apple-emoji/blob/main/LICENSE)
- **Apple Color Emoji 位图版权归 Apple Inc.**，本项目未获再分发授权。仓库不附带位图素材，安装包仅为本机自用构建，请勿二次分发。详见 [THIRD-PARTY.md](https://github.com/Cheney34/chiron-apple-emoji/blob/main/THIRD-PARTY.md)
- Chiron GoRound TC 依其原仓库授权；Merriweather 为 SIL OFL 1.1

完整改动记录见 [CHANGELOG.md](https://github.com/Cheney34/chiron-apple-emoji/blob/main/CHANGELOG.md)。
