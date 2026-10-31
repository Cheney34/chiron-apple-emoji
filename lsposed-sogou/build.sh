#!/usr/bin/env bash
# 构建 Apple Emoji Sogou LSPosed 模块
#
# 依赖：
#   JDK 17+、Android SDK build-tools 34、platform android-34
#   XposedBridgeAPI-82.jar 放到 libs/ 下（见 libs/README.md）
#
# 用法：
#   ./build.sh
#   ANDROID_SDK=/path/to/sdk ./build.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

SDK="${ANDROID_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}}"
# build-tools 版本随 SDK 安装而异，取已安装的最高版本（GitHub Actions 上是 34.x/35.x）
if [ -n "${BUILD_TOOLS:-}" ]; then
  BT="$SDK/build-tools/$BUILD_TOOLS"
else
  BT=$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sed 's#/$##' | sort -V | tail -1)
fi
AJAR="$SDK/platforms/android-34/android.jar"
[ -f "$AJAR" ] || AJAR=$(ls -d "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1)
XPOSED="${XPOSED_API_JAR:-$HERE/libs/XposedBridgeAPI-82.jar}"

[ -x "$BT/aapt2" ] || { echo "找不到 aapt2：$BT/aapt2"; echo "请设置 ANDROID_SDK 指向 SDK 根目录"; exit 1; }
[ -f "$AJAR" ]     || { echo "找不到 android.jar：$AJAR"; exit 1; }
[ -f "$XPOSED" ]   || { echo "找不到 XposedBridgeAPI-82.jar：$XPOSED"; echo "见 libs/README.md"; exit 1; }
[ -f assets/payload.zip ] || {
  cat <<'EOF'
缺少 assets/payload.zip。
该文件含 Apple 彩色 emoji 位图，不随仓库分发，请用你自己的素材生成：

  python3 tools/make_payload.py --src /path/to/img-apple-160 --out assets/payload.zip

EOF
  exit 1
}

rm -rf build gen classes dex
mkdir -p build gen classes dex

echo "[1/7] aapt2 compile"
"$BT/aapt2" compile --dir res -o build/res.zip

echo "[2/7] aapt2 link"
"$BT/aapt2" link -o build/app.unsigned.apk \
  -I "$AJAR" \
  --manifest AndroidManifest.xml \
  -A assets \
  --java gen \
  --min-sdk-version 26 --target-sdk-version 34 \
  build/res.zip

echo "[3/7] javac"
javac --release 17 -nowarn -encoding UTF-8 -classpath "$AJAR:$XPOSED" -d classes \
  $(find src gen -name '*.java')

echo "[4/7] d8"
find classes -name '*.class' > build/classes.txt
"$BT/d8" --lib "$AJAR" --min-api 26 --release --output dex @build/classes.txt

echo "[5/7] package"
cp build/app.unsigned.apk build/app.apk
(cd dex && zip -q -X ../build/app.apk classes.dex)
"$BT/zipalign" -f -p 4 build/app.apk build/app.aligned.apk

echo "[6/7] keystore"
KS="${KEYSTORE:-$HERE/build/debug.keystore}"
mkdir -p "$(dirname "$KS")"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" \
    -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
  echo "  已生成调试签名 $KS"
  echo "  ⚠ 如果要覆盖安装社区里已分发的版本，请改用同一份签名，否则会提示签名冲突"
fi

echo "[7/7] sign"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out build/app-signed.apk build/app.aligned.apk

ls -lh build/app-signed.apk
"$BT/apksigner" verify --print-certs build/app-signed.apk | head -4
