import Foundation

var passed = 0
var failed = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("FAIL \(name)")
    }
}

let now = Date()

func sample(_ lat: Double, _ lon: Double,
            accuracy: Double = 12.0, altitude: Double = 35.0,
            simulated: Bool? = nil, accessory: Bool? = nil,
            age: TimeInterval = 0) -> LocationSample {
    LocationSample(latitude: lat, longitude: lon,
                   horizontalAccuracy: accuracy, altitude: altitude,
                   speed: 0, course: 0,
                   timestamp: now.addingTimeInterval(-age),
                   isSimulatedBySoftware: simulated,
                   isProducedByAccessory: accessory)
}

func ids(_ findings: [Finding]) -> Set<String> { Set(findings.map(\.id)) }

// 中国时区 UTC+8
let cst = 8.0

// 1. 真实定位：有抖动、精度不一、无模拟标记 → 不该报警
let realSamples = [
    sample(23.149512, 113.457661),
    sample(23.149518, 113.457658),
    sample(23.149509, 113.457665),
    sample(23.149521, 113.457652),
]
let real = TamperDetector.checkLocation(realSamples, deviceTimeZoneOffsetHours: cst)
check("真实抖动定位不报静止", !ids(real).contains("location.static"))
check("真实定位不报模拟标记", !ids(real).contains("location.simulated"))

// 2. 系统明确标记模拟 → 必须报 danger
let flagged = TamperDetector.checkLocation(
    [sample(23.149515, 113.457655, simulated: true)], deviceTimeZoneOffsetHours: cst)
check("系统模拟标记被识别", ids(flagged).contains("location.simulated"))
check("系统模拟标记为高风险", TamperDetector.overallSeverity(flagged) == .danger)

// 3. 坐标完全静止（模拟器固定值）→ 报静止
let staticSamples = (0..<5).map { _ in sample(23.149515, 113.457655) }
let stat = TamperDetector.checkLocation(staticSamples, deviceTimeZoneOffsetHours: cst)
check("固定坐标被识别为静止", ids(stat).contains("location.static"))

// 4. 模拟器默认值（精度5/海拔0）
let defaults = TamperDetector.checkLocation(
    [sample(23.1, 113.4, accuracy: 5.0, altitude: 0.0)], deviceTimeZoneOffsetHours: cst)
check("模拟器默认值被识别", ids(defaults).contains("location.defaults"))

// 5. 时区严重不符：伦敦坐标 + 中国时区
let tzBad = TamperDetector.checkLocation(
    [sample(51.5074, -0.1278)], deviceTimeZoneOffsetHours: cst)
check("跨时区模拟被识别", ids(tzBad).contains("location.timezone"))
check("跨时区为高风险", TamperDetector.overallSeverity(tzBad) == .danger)

// 6. 中国境内跨时区不应误报（乌鲁木齐 87.6°E，UTC+8）
let urumqi = TamperDetector.checkLocation(
    [sample(43.8256, 87.6168)], deviceTimeZoneOffsetHours: cst)
check("乌鲁木齐不误报时区", !ids(urumqi).contains("location.timezone"))

// 7. 外部配件提供坐标
let acc = TamperDetector.checkLocation(
    [sample(23.1, 113.4, accessory: true)], deviceTimeZoneOffsetHours: cst)
check("外部配件坐标被识别", ids(acc).contains("location.accessory"))

// 8. 干净进程环境 → 无注入告警
let cleanEnv = InjectionEnvironment(
    dyldImagePaths: ["/usr/lib/libSystem.B.dylib", "/System/Library/Frameworks/UIKit.framework/UIKit"],
    environment: [:], isDebuggerAttached: false,
    existingSuspiciousPaths: [], hostHasSimulationEntitlement: false)
check("干净环境无注入告警", TamperDetector.checkInjection(cleanEnv).isEmpty)

// 9. 注入库被识别
let injected = InjectionEnvironment(
    dyldImagePaths: ["/usr/lib/libSystem.B.dylib", "/var/jb/usr/lib/libellekit.dylib"],
    environment: [:], isDebuggerAttached: false,
    existingSuspiciousPaths: [], hostHasSimulationEntitlement: false)
check("ellekit 注入被识别", ids(TamperDetector.checkInjection(injected)).contains("inject.dyld"))

// 10. Frida 被识别
let frida = InjectionEnvironment(
    dyldImagePaths: ["/usr/lib/libSystem.B.dylib", "/usr/lib/frida/frida-agent.dylib"],
    environment: [:], isDebuggerAttached: false,
    existingSuspiciousPaths: [], hostHasSimulationEntitlement: false)
check("Frida 被识别", ids(TamperDetector.checkInjection(frida)).contains("inject.dyld"))

// 11. DYLD_INSERT_LIBRARIES 被识别
let envInject = InjectionEnvironment(
    dyldImagePaths: ["/usr/lib/libSystem.B.dylib"],
    environment: ["DYLD_INSERT_LIBRARIES": "/var/jb/usr/lib/libhooker.dylib"],
    isDebuggerAttached: false, existingSuspiciousPaths: [],
    hostHasSimulationEntitlement: false)
check("环境变量注入被识别", ids(TamperDetector.checkInjection(envInject)).contains("inject.env"))

// 12. 调试器附加被识别
let debugged = InjectionEnvironment(
    dyldImagePaths: ["/usr/lib/libSystem.B.dylib"], environment: [:],
    isDebuggerAttached: true, existingSuspiciousPaths: [],
    hostHasSimulationEntitlement: false)
check("调试器附加被识别", ids(TamperDetector.checkInjection(debugged)).contains("inject.debugger"))

// 13. 越狱路径被识别
let jbPaths = InjectionEnvironment(
    dyldImagePaths: ["/usr/lib/libSystem.B.dylib"], environment: [:],
    isDebuggerAttached: false, existingSuspiciousPaths: ["/var/jb/bin/sh"],
    hostHasSimulationEntitlement: false)
check("越狱路径被识别", ids(TamperDetector.checkInjection(jbPaths)).contains("inject.paths"))

// 14. 持有模拟权限被识别（检测模拟工具自身）
let entitled = InjectionEnvironment(
    dyldImagePaths: ["/usr/lib/libSystem.B.dylib"], environment: [:],
    isDebuggerAttached: false, existingSuspiciousPaths: [],
    hostHasSimulationEntitlement: true)
check("持有模拟权限被识别", ids(TamperDetector.checkInjection(entitled)).contains("inject.entitlement"))

// 15. 陈旧时间戳只给提示级
let stale = TamperDetector.checkLocation(
    [sample(23.149515, 113.457655, age: 60)], deviceTimeZoneOffsetHours: cst)
check("陈旧时间戳被识别", ids(stale).contains("location.stale"))
check("陈旧时间戳不是高风险", TamperDetector.overallSeverity(stale) == .info)

// 16. 去重计数正确
check("去重计数正确", TamperDetector.distinctCoordinateCount(realSamples) == 4)

// 17. 综合判定：模拟工具全特征
let full = TamperDetector.checkLocation(
    staticSamples.map { LocationSample(latitude: $0.latitude, longitude: $0.longitude,
        horizontalAccuracy: 5.0, altitude: 0.0, speed: 0, course: 0,
        timestamp: $0.timestamp, isSimulatedBySoftware: true, isProducedByAccessory: nil) },
    deviceTimeZoneOffsetHours: cst) + TamperDetector.checkInjection(entitled)
check("综合判定为高风险", TamperDetector.overallSeverity(full) == .danger)
check("综合判定命中多项", full.count >= 4)

// 18. 空样本不崩溃
check("空样本安全", TamperDetector.checkLocation([], deviceTimeZoneOffsetHours: cst).isEmpty)

print("检测规则测试：通过 \(passed) 项，失败 \(failed) 项")
if failed > 0 { exit(1) }
