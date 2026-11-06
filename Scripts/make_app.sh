#!/bin/bash
# 组 Curtain.app：release 构建 + Info.plist + 签名。
#
# 默认用本地自签名证书 "Curtain Dev" 签名。固定证书后，TCC（辅助功能/屏幕录制）
# 的授权可以跨重新编译保留；ad-hoc 签名每次重编译都会变，TCC 会报
# "Failed to match existing code requirement" 而拒绝生效。
#
# 覆盖签名身份：
#   SIGN_ID="Apple Development: xxx" ./Scripts/make_app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Curtain.app"

if [ -z "${SIGN_ID:-}" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Curtain Dev"'; then
        SIGN_ID="Curtain Dev"
    else
        SIGN_ID="-"
    fi
fi

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
if [ "$SIGN_ID" = "-" ]; then
    echo "    警告：没有固定签名证书，退回 ad-hoc。每次重编译后 TCC 授权都会失效。"
    codesign --force --sign - "$APP/Contents/MacOS/curtainctl"
    codesign --force --sign - "$APP"
else
    codesign --force --timestamp=none --sign "$SIGN_ID" "$APP/Contents/MacOS/curtainctl"
    codesign --force --timestamp=none --sign "$SIGN_ID" "$APP"
fi

echo "==> 签名信息"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|Signature|TeamIdentifier" || true

echo "==> done: $APP"
echo "启动：open $APP"
echo "CLI： $APP/Contents/MacOS/curtainctl status"
