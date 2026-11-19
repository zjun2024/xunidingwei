#!/usr/bin/env bash
# 检测规则的纯逻辑测试。不需要 iOS SDK，Linux 上也能跑。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

SWIFTC="${SWIFTC:-swiftc}"
LINK_FLAGS=()
if [ "$(uname -s)" = "Linux" ]; then
    # Linux 上的 Swift 工具链默认用 gold 链接器，通常不可用，改用 lld。
    LINK_FLAGS=(-use-ld=lld)
fi

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

"$SWIFTC" -O "${LINK_FLAGS[@]}" \
    "$ROOT/ios-app/DetectionLab/Engine/TamperDetector.swift" \
    "$HERE/main.swift" \
    -o "$BUILD/detection-tests"

"$BUILD/detection-tests"
