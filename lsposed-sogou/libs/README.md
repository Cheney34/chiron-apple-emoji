# libs/

构建需要 `XposedBridgeAPI-82.jar`。本仓库不附带该 jar，请自行获取，二选一：

## 方式一：Maven 仓库（推荐）

Maven Central 上的坐标是 `de.robv.android.xposed:api:82`（不带 sources/javadoc）。  
直接下载：

```bash
curl -fL -o libs/XposedBridgeAPI-82.jar \
  https://repo1.maven.org/maven2/de/robv/android/xposed/api/82/api-82.jar
```

## 方式二：从 Xposed 官方仓库

<https://github.com/rovo89/XposedBridge> 里的 API 编译产物，重命名为 `XposedBridgeAPI-82.jar` 放进本目录。

## 说明

这里用的是 **API 82** 的旧接口（`de.robv.android.xposed.IXposedHookLoadPackage` 等），
LSPosed 1.7 ~ 1.10 全兼容。不要换成新版 `Xposed` 依赖，否则 `xposed_init` 的入口类签名不匹配。
