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

# 这套桩只适用于 Linux：桩里重新声明了 CFTypeRef、NSObject.perform 等，
# 在 macOS 上这些都是真实符号，会报重复声明。macOS 上由 Xcode 真实编译覆盖。
if [ "$(uname -s)" = "Darwin" ]; then
    echo "跳过：macOS 上由 Xcode 真实编译覆盖，无需桩测试"
    exit 0
fi

SWIFTC="${SWIFTC:-swiftc}"
# Linux 上的 Swift 工具链默认用 gold 链接器，通常不可用，改用 lld。
LINK_FLAGS=(-use-ld=lld)
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

# 日志模块只用于真机排障，逻辑测试不需要，直接生成空实现。
cat > "$BUILD/DiagnosticLog.swift" <<'SWIFTLOG'
enum DiagnosticLog {
    static func step(_ message: String) {}
    static func failure(_ message: String) {}
}
SWIFTLOG

# 画中画保活依赖 AVKit，Linux 上给一个同接口的空实现，
# 只验证状态机联动（开关是否被正确记录与调用），不验证真实画中画行为。
cat > "$BUILD/PiPKeepAlive.swift" <<'SWIFTPIP'
import Foundation

final class PiPKeepAlive {
    static let shared = PiPKeepAlive()
    static var isSupported: Bool { true }
    private(set) var lastError: String?
    private(set) var startedCaptions: [String] = []
    private(set) var isRunning = false

    private init() {}

    func start(caption: String) {
        startedCaptions.append(caption)
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}
SWIFTPIP

# 状态机只依赖 Foundation，去掉平台框架的 import。
sed -e 's/^import Combine$//' -e 's/^import SwiftUI$//' -e 's/^import UIKit$//' \
    "$APP/Engine/LocSimStore.swift" > "$BUILD/LocSimStore.swift"

"$SWIFTC" -O "${LINK_FLAGS[@]}" \
    "$HERE/PlatformStubs.swift" \
    "$HERE/ObjCStubs.swift" \
    "$HERE/SwiftUIStubs.swift" \
    "$HERE/RuntimeStubs.swift" \
    "$APP/Models.swift" \
    "$APP/Generated/LocationData.swift" \
    "$BUILD/LocSimEngine.swift" \
    "$BUILD/DiagnosticLog.swift" \
    "$BUILD/PiPKeepAlive.swift" \
    "$BUILD/LocSimStore.swift" \
    "$BUILD/main.swift" \
    -o "$BUILD/logic-tests"

"$BUILD/logic-tests"
