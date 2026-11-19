#!/bin/bash
# GitHub Release 用的 ad-hoc 产物：zip、DMG 和各自的 SHA-256 sidecar。
# 不依赖 Developer ID、公证或付费证书。
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ZIP="dist/Curtain-${VERSION}.zip"
DMG="dist/Curtain-${VERSION}.dmg"
CHECKSUMS="dist/Curtain-${VERSION}.SHA256SUMS"
DMG_ROOT="dist/.dmg-root"

./Scripts/make_app.sh
mkdir -p dist
rm -f "$ZIP" "$ZIP.sha256" "$DMG" "$DMG.sha256" "$CHECKSUMS"
rm -rf "$DMG_ROOT"
ditto -c -k --norsrc --keepParent build/Curtain.app "$ZIP"
shasum -a 256 "$ZIP" > "$ZIP.sha256"

mkdir -p "$DMG_ROOT"
cp -R build/Curtain.app "$DMG_ROOT/Curtain.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG"
if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from \
        --format UDZO \
        --volumeName "Curtain" \
        "$DMG_ROOT" \
        "$DMG" >/dev/null
else
    hdiutil create \
        -volname "Curtain" \
        -srcfolder "$DMG_ROOT" \
        -ov \
        -format UDZO \
        "$DMG" >/dev/null
fi
rm -rf "$DMG_ROOT"
shasum -a 256 "$DMG" > "$DMG.sha256"
(cd dist && shasum -a 256 \
    "Curtain-${VERSION}.zip" \
    "Curtain-${VERSION}.dmg" > "Curtain-${VERSION}.SHA256SUMS")

codesign --verify --deep --strict --verbose=2 build/Curtain.app
plutil -lint build/Curtain.app/Contents/Info.plist

echo
echo "==> GitHub Release 产物"
echo "$ZIP"
echo "$ZIP.sha256"
echo "$DMG"
echo "$DMG.sha256"
echo "$CHECKSUMS"
echo
echo "用户首次打开 ad-hoc 构建时，二选一："
echo "  右键 Curtain.app → 打开"
echo "  xattr -dr com.apple.quarantine /Applications/Curtain.app"
echo
echo "发布："
echo "  gh release create v${VERSION} '$ZIP' '$ZIP.sha256' '$DMG' '$DMG.sha256' '$CHECKSUMS' \\"
echo "    --title 'Curtain ${VERSION}' --notes-file RELEASE_NOTES.md"
