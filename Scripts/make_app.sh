#!/bin/bash
# 组 Curtain.app：release 构建 + Info.plist + 签名。
#
# 默认 ad-hoc 签名，不依赖任何证书。代价：每次重新编译后，系统设置里的
# TCC 授权（设备控制和数据访问 / 录屏与系统录音）需要把 Curtain.app 取消再勾一次
# ——ad-hoc 的代码身份就是 cdhash，代码变了就匹配不上。
#
# 想避免反复授权，可以指定固定签名身份（可选）：
#   SIGN_ID="某张代码签名证书的 CN" INSTALL=1 ./Scripts/make_app.sh
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
if [ "$SIGN_ID" = "-" ]; then
    echo "    ad-hoc 签名：重装后需要在系统设置里把 Curtain.app 取消再勾一次。"
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

if [ "${INSTALL:-0}" = "1" ]; then
    echo "==> install to /Applications/Curtain.app"
    pkill -f "Curtain.app/Contents/MacOS/curtaind" 2>/dev/null || true
    sleep 1
    rm -rf /Applications/Curtain.app
    cp -R "$APP" /Applications/Curtain.app
    echo "已安装：/Applications/Curtain.app"
fi
