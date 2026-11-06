#!/bin/bash
# 组 Curtain.app：release 构建 + Info.plist + 签名。
# 想避免每次重编译后 TCC 权限失效，请先建一张自签名证书再执行：
#   SIGN_ID="Curtain Dev" ./Scripts/make_app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Curtain.app"
SIGN_ID="${SIGN_ID:--}"

echo "==> swift build -c release"
swift build -c release --product curtaind
swift build -c release --product curtainctl

BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/curtaind" "$APP/Contents/MacOS/curtaind"
cp "$BIN_DIR/curtainctl" "$APP/Contents/MacOS/curtainctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> codesign (identity: $SIGN_ID)"
codesign --force --options runtime --sign "$SIGN_ID" "$APP/Contents/MacOS/curtainctl"
codesign --force --options runtime --sign "$SIGN_ID" "$APP"

echo "==> done: $APP"
echo "启动：open $APP    （首次需要在系统设置里授予 屏幕录制 + 辅助功能）"
echo "CLI： $APP/Contents/MacOS/curtainctl status"
