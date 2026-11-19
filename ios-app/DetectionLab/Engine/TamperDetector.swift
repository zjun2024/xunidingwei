import Foundation

/// 一条定位样本。只保留检测需要的字段，不依赖 CoreLocation，
/// 这样检测规则可以在非 iOS 环境里做单元测试。
struct LocationSample {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double
    let speed: Double
    let course: Double
    let timestamp: Date
    /// CLLocation.sourceInformation?.isSimulatedBySoftware（iOS 15+）
    let isSimulatedBySoftware: Bool?
    /// CLLocation.sourceInformation?.isProducedByAccessory
    let isProducedByAccessory: Bool?
}

/// 进程环境快照，同样与平台解耦，便于测试。
struct InjectionEnvironment {
    let dyldImagePaths: [String]
    let environment: [String: String]
    let isDebuggerAttached: Bool
    let existingSuspiciousPaths: [String]
    /// 本进程是否持有定位模拟权限；正常 App 不该有。
    let hostHasSimulationEntitlement: Bool?
}

enum Severity: Int, Comparable {
    case info = 0
    case warning = 1
    case danger = 2

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .info: return "提示"
        case .warning: return "可疑"
        case .danger: return "高风险"
        }
    }
}

struct Finding: Identifiable {
    let id: String
    let title: String
    let severity: Severity
    let detail: String
}

/// 反作弊检测规则集合。
///
/// 分两类：坐标特征检测（定位是否被系统级模拟）与进程环境检测（是否被注入）。
/// 全部规则都是纯函数，输入固定则输出固定，方便回归测试。
enum TamperDetector {

    // MARK: - 阈值

    /// 时区与经度的允许偏差。中国横跨多个时区但统一用 UTC+8，
    /// 乌鲁木齐（东经 87°）与东八区的理论偏差约 2.2 小时，故下限取 4 小时。
    static let timezoneWarningHours = 4.0
    static let timezoneDangerHours = 6.0

    /// 认为「坐标完全静止」所需的最少样本数与精度位数。
    static let staticSampleCount = 4
    static let staticDecimals = 6

    /// 模拟器常见的默认值特征。
    static let simulatorAccuracy: Double = 5.0
    static let simulatorAltitude: Double = 0.0

    /// dyld 镜像路径中出现即判定注入的特征串。
    static let injectionMarkers = [
        "/var/jb", "substrate", "libhooker", "ellekit",
        "substitute", "tweakinject", "frida", "cycript",
    ]

    // MARK: - 坐标检测

    static func checkLocation(_ samples: [LocationSample],
                              deviceTimeZoneOffsetHours: Double) -> [Finding] {
        guard let latest = samples.last else { return [] }
        var findings: [Finding] = []

        // 1. 系统自己给出的模拟标记，最权威，无法靠改数值绕过。
        if latest.isSimulatedBySoftware == true {
            findings.append(Finding(
                id: "location.simulated",
                title: "系统标记该坐标由软件模拟",
                severity: .danger,
                detail: "CoreLocation 的 sourceInformation 明确表示此坐标不是真实硬件产生。"))
        }

        if latest.isProducedByAccessory == true {
            findings.append(Finding(
                id: "location.accessory",
                title: "坐标由外部配件提供",
                severity: .warning,
                detail: "sourceInformation 显示坐标来自外部设备，而非手机自身定位。"))
        }

        // 2. 真实 GPS 必然抖动；多次采样完全一致说明是注入的固定值。
        let staticCount = distinctCoordinateCount(samples)
        if samples.count >= staticSampleCount, staticCount == 1 {
            findings.append(Finding(
                id: "location.static",
                title: "坐标长时间完全静止",
                severity: .danger,
                detail: "\(samples.count) 次采样的小数点后 \(staticDecimals) 位完全相同。真实定位会持续抖动，固定值通常来自模拟。"))
        }

        // 3. 模拟器默认值：精度恰好 5 米、海拔恰好 0 米。
        if latest.horizontalAccuracy == simulatorAccuracy && latest.altitude == simulatorAltitude {
            findings.append(Finding(
                id: "location.defaults",
                title: "精度与海拔符合模拟器默认值",
                severity: .warning,
                detail: "水平精度恰好 \(simulatorAccuracy) 米、海拔恰好 \(simulatorAltitude) 米，这是常见模拟工具的默认参数。"))
        }

        // 4. 坐标所在时区与手机时区是否对得上。
        let expectedOffset = latest.longitude / 15.0
        let drift = abs(expectedOffset - deviceTimeZoneOffsetHours)
        if drift > timezoneDangerHours {
            findings.append(Finding(
                id: "location.timezone",
                title: "坐标时区与设备时区严重不符",
                severity: .danger,
                detail: String(format: "坐标推算时区约 UTC%+.0f，设备时区 UTC%+.0f，相差 %.1f 小时。",
                               expectedOffset, deviceTimeZoneOffsetHours, drift)))
        } else if drift > timezoneWarningHours {
            findings.append(Finding(
                id: "location.timezone",
                title: "坐标时区与设备时区不符",
                severity: .warning,
                detail: String(format: "坐标推算时区约 UTC%+.0f，设备时区 UTC%+.0f，相差 %.1f 小时。",
                               expectedOffset, deviceTimeZoneOffsetHours, drift)))
        }

        // 5. 时间戳陈旧。
        let age = Date().timeIntervalSince(latest.timestamp)
        if age > 10 {
            findings.append(Finding(
                id: "location.stale",
                title: "定位时间戳偏旧",
                severity: .info,
                detail: String(format: "最新样本距今 %.0f 秒。", age)))
        }

        return findings
    }

    /// 把坐标按固定精度取整后去重计数。
    static func distinctCoordinateCount(_ samples: [LocationSample]) -> Int {
        let scale = pow(10.0, Double(staticDecimals))
        let keys = Set(samples.map {
            "\(Int(($0.latitude * scale).rounded()))_\(Int(($0.longitude * scale).rounded()))"
        })
        return keys.count
    }

    // MARK: - 注入检测

    static func checkInjection(_ env: InjectionEnvironment) -> [Finding] {
        var findings: [Finding] = []

        // 1. dyld 加载了越狱/注入相关的库。
        let hits = Set(env.dyldImagePaths.compactMap { path -> String? in
            let lower = path.lowercased()
            return injectionMarkers.first { lower.contains($0) }
        })
        if !hits.isEmpty {
            findings.append(Finding(
                id: "inject.dyld",
                title: "检测到注入库",
                severity: .danger,
                detail: "进程加载了以下特征库：\(hits.sorted().joined(separator: "、"))。"))
        }

        // 2. 通过环境变量强制加载动态库。
        if let insert = env.environment["DYLD_INSERT_LIBRARIES"], !insert.isEmpty {
            findings.append(Finding(
                id: "inject.env",
                title: "环境变量注入了动态库",
                severity: .danger,
                detail: "DYLD_INSERT_LIBRARIES = \(insert)"))
        }

        // 3. 被调试器附加，可能正在被动态分析。
        if env.isDebuggerAttached {
            findings.append(Finding(
                id: "inject.debugger",
                title: "进程正被调试器附加",
                severity: .warning,
                detail: "检测到 P_TRACED 标志，可能处于调试或动态分析状态。"))
        }

        // 4. 文件系统上存在越狱痕迹。
        if !env.existingSuspiciousPaths.isEmpty {
            findings.append(Finding(
                id: "inject.paths",
                title: "存在越狱环境痕迹",
                severity: .warning,
                detail: "以下路径存在：\(env.existingSuspiciousPaths.joined(separator: "、"))。"))
        }

        // 5. 本进程持有定位模拟权限，正常 App 不该有。
        if env.hostHasSimulationEntitlement == true {
            findings.append(Finding(
                id: "inject.entitlement",
                title: "本 App 自身持有定位模拟权限",
                severity: .danger,
                detail: "普通 App 不应具备 com.apple.locationd.simulation，具备即说明它本身就是模拟工具。"))
        }

        return findings
    }

    // MARK: - 汇总

    static func overallSeverity(_ findings: [Finding]) -> Severity {
        findings.map(\.severity).max() ?? .info
    }

    static func summary(_ findings: [Finding]) -> String {
        guard !findings.isEmpty else {
            return "未发现异常，本次环境与坐标看起来是真实的。"
        }
        switch overallSeverity(findings) {
        case .danger: return "发现高风险特征，可以判定定位被篡改或进程被注入。"
        case .warning: return "发现可疑特征，建议结合更多信号复核。"
        case .info: return "仅有提示级信息，不构成判定依据。"
        }
    }
}
