#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# CLT 自带的 SwiftPM 不会自动加载 Swift Testing 宏插件；Xcode 工具链不需要这一步。
PLUGIN="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -f "$PLUGIN" ]; then
    exec swift test \
        -Xswiftc -load-plugin-library \
        -Xswiftc "$PLUGIN" \
        "$@"
fi

exec swift test "$@"
