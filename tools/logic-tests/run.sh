#!/usr/bin/env bash
# 在没有 Xcode / iOS SDK 的机器上，用桩替代 UIKit、SwiftUI、CoreLocation、
# AVFoundation，编译并运行引擎与状态机的真实逻辑。
#
# 用法: tools/logic-tests/run.sh
#
# 需要 swiftc（Linux 或 macOS 都可以）。macOS 上直接用系统 swiftc 即可；
# Linux 上需要 Swift 5.9+ 工具链。
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

# 引擎在测试里不需要 Security 的私有符号，去掉那两行声明后由桩提供。
python3 - "$APP/Engine/LocSimEngine.swift" "$BUILD/LocSimEngine.swift" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
text = text.replace("import CoreLocation\n", "").replace("import Security\n", "")
text = text.replace(
    '''// SecTask 是 Security 框架里的私有 SPI，没有公开头文件，这里手写声明。
typealias SecTaskRef = CFTypeRef
@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> SecTaskRef?
@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(_ task: SecTaskRef, _ entitlement: CFString, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFTypeRef?''',
    "typealias SecTaskRef = CFTypeRef")
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
