#!/usr/bin/env bash
# 在没有 Xcode / iOS SDK 的机器上，用桩替代 UIKit、SwiftUI、CoreLocation、
# AVFoundation，编译并运行引擎与状态机的真实逻辑。
#
# 用法: tools/logic-tests/run.sh
#
# 需要 swiftc（Linux 或 macOS 都可以）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
APP="$ROOT/ios-app/Xunidingwei"

SWIFTC="${SWIFTC:-swiftc}"
# Linux 上的 Swift 工具链默认用 gold 链接器，通常不可用，改用 lld。
LINK_FLAGS=()
if [ "$(uname -s)" = "Linux" ]; then
    LINK_FLAGS=(-use-ld=lld)
fi
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# 引擎去掉平台框架的 import 和 SecTask 的 @_silgen_name 声明，
# 改由 ObjCStubs.swift 提供同名函数，这样在 Linux 上也能链接。
python3 - "$APP/Engine/LocSimEngine.swift" "$BUILD/LocSimEngine.swift" <<'PY'
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
text = text.replace("import CoreLocation\n", "").replace("import Security\n", "")
text = re.sub(r"typealias XdwSecTask = CFTypeRef\n", "", text)
text = re.sub(r'@_silgen_name\("SecTask\w+"\)\nfunc SecTask\w+\(.*?\) -> [^\n]*\n', "", text, flags=re.S)
open(dst, "w", encoding="utf-8").write(text)
PY

# 顶层代码只能写在 main.swift 里。
cp "$HERE/StoreTests.swift" "$BUILD/main.swift"

# 状态机只依赖 Foundation，去掉平台框架的 import。
sed -e 's/^import Combine$//' -e 's/^import SwiftUI$//' -e 's/^import UIKit$//' \
    "$APP/Engine/LocSimStore.swift" > "$BUILD/LocSimStore.swift"

# macOS 自带 bash 3.2，set -u 下直接展开空数组会报错。
"$SWIFTC" -O ${LINK_FLAGS[@]+"${LINK_FLAGS[@]}"} \
    "$HERE/PlatformStubs.swift" \
    "$HERE/ObjCStubs.swift" \
    "$HERE/SwiftUIStubs.swift" \
    "$HERE/RuntimeStubs.swift" \
    "$APP/Models.swift" \
    "$APP/Generated/LocationData.swift" \
    "$BUILD/LocSimEngine.swift" \
    "$BUILD/LocSimStore.swift" \
    "$BUILD/main.swift" \
    -o "$BUILD/logic-tests"

"$BUILD/logic-tests"
