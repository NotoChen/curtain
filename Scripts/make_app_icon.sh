#!/bin/bash
# 从 1024px 源图生成 macOS iconset 和 AppIcon.icns。
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="${1:-Resources/AppIconSource.png}"
OUTPUT="Resources/AppIcon.icns"
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/curtain-appicon.XXXXXX")/AppIcon.iconset"

cleanup() {
    rm -rf "$(dirname "$ICONSET")"
}
trap cleanup EXIT

if [ ! -f "$SOURCE" ]; then
    echo "找不到图标源图：$SOURCE" >&2
    exit 1
fi

mkdir -p "$ICONSET"

render() {
    local pixels="$1"
    local name="$2"
    sips -z "$pixels" "$pixels" "$SOURCE" --out "$ICONSET/$name" >/dev/null
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns -o "$OUTPUT" "$ICONSET"

echo "已生成：$OUTPUT"
