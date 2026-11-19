import CoreLocation
import Foundation
import Security

// SecTask 是 Security 框架里的私有 SPI，没有公开头文件，这里手写声明。
// 自定义类型名，避免与 SDK 里可能存在的同名类型冲突。
typealias XdwSecTask = CFTypeRef
@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> XdwSecTask?
@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(_ task: XdwSecTask, _ entitlement: CFString, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFTypeRef?

/// 定位模拟引擎。
///
/// 通过 CoreLocation 私有类 `CLSimulationManager` 驱动 locationd，
/// 需要 `com.apple.locationd.simulation` 权限（见 entitlements）。
///
/// iOS 上该类型由 Private/CLSimulationManager.h 声明，编译期即真实类型；
/// Linux 逻辑测试没有这个头文件，退化为运行时反射。
final class LocSimEngine {
    enum EngineError: LocalizedError {
        case classUnavailable
        case noEntitlement
        case callFailed(String)

        var errorDescription: String? {
            switch self {
            case .classUnavailable:
                return "这台系统上找不到 CLSimulationManager（仅 iOS 15 及以上支持）"
            case .noEntitlement:
                return "缺少 com.apple.locationd.simulation 权限，请用仓库里的 ipa 安装（TrollStore 会保留签名里的权限）"
            case .callFailed(let name):
                return "调用 \(name) 失败"
            }
        }
    }

    static let shared = LocSimEngine()

    /// 当前正在模拟的坐标，nil 表示已恢复真实定位。
    private(set) var activeTarget: LocationTarget?
    private(set) var startedAt: Date?

    private static let requiredSelectors = [
        "clearSimulatedLocations",
        "appendSimulatedLocation:",
        "flush",
        "startLocationSimulation",
        "stopLocationSimulation",
    ]

    private var manager: AnyObject?

    private init() {}

    // MARK: - 自检

    /// 系统里有没有这个类。
    var isClassAvailable: Bool {
        #if canImport(ObjectiveC)
        return NSClassFromString("CLSimulationManager") != nil
        #else
        return false
        #endif
    }

    /// 模拟所需的方法是否齐全。
    var isInterfaceComplete: Bool {
        #if canImport(ObjectiveC)
        guard let instance = makeRawManager() else { return false }
        return Self.requiredSelectors.allSatisfy {
            instance.responds(to: NSSelectorFromString($0))
        }
        #else
        return false
        #endif
    }

    /// 运行时的权限检查：直接问内核“我这个进程有没有这条权限”。
    var hasSimulationEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.locationd.simulation" as CFString, nil
        ) else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }

    // MARK: - 实例化

    private func makeRawManager() -> NSObject? {
        #if canImport(ObjectiveC)
        return CLSimulationManager()
        #else
        return nil
        #endif
    }

    private func makeManager() throws -> AnyObject {
        if let manager { return manager }
        guard let instance = makeRawManager() else {
            DiagnosticLog.failure("取不到 CLSimulationManager 实例")
            throw EngineError.classUnavailable
        }
        guard hasSimulationEntitlement else {
            DiagnosticLog.failure("缺少 locationd.simulation 权限")
            throw EngineError.noEntitlement
        }
        DiagnosticLog.step("CLSimulationManager 实例已创建，权限检查通过")
        manager = instance
        return instance
    }

    // MARK: - 调用

    private func appendLocation(_ location: CLLocation, to manager: AnyObject) throws {
        #if canImport(ObjectiveC)
        guard let sim = manager as? CLSimulationManager else { throw EngineError.classUnavailable }
        sim.appendSimulatedLocation(location)
        #else
        guard let object = manager as? NSObject else { throw EngineError.classUnavailable }
        let selector = NSSelectorFromString("appendSimulatedLocation:")
        guard object.responds(to: selector) else { throw EngineError.callFailed("appendSimulatedLocation:") }
        _ = object.perform(selector, with: location)
        #endif
    }

    private func call(_ name: String, on manager: AnyObject) throws {
        #if canImport(ObjectiveC)
        guard let sim = manager as? CLSimulationManager else { throw EngineError.classUnavailable }
        switch name {
        case "clearSimulatedLocations": sim.clearSimulatedLocations()
        case "flush": sim.flush()
        case "startLocationSimulation": sim.startLocationSimulation()
        case "stopLocationSimulation": sim.stopLocationSimulation()
        default: throw EngineError.callFailed(name)
        }
        #else
        guard let object = manager as? NSObject else { throw EngineError.classUnavailable }
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { throw EngineError.callFailed(name) }
        _ = object.perform(selector)
        #endif
    }

    private func postTimezoneUpdate() {
        CFNotificationCenterPostNotificationWithOptions(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("AutomaticTimeZoneUpdateNeeded" as CFString),
            nil, nil,
            kCFNotificationDeliverImmediately
        )
    }

    // MARK: - 操作

    /// 开始（或切换到）某个虚拟位置。
    func start(_ target: LocationTarget) throws {
        let manager = try makeManager()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )

        DiagnosticLog.step("开始模拟 -> \(target.coordinateText) (\(target.label))")

        try call("stopLocationSimulation", on: manager)
        DiagnosticLog.step("stopLocationSimulation 完成")
        try call("clearSimulatedLocations", on: manager)
        DiagnosticLog.step("clearSimulatedLocations 完成")
        try appendLocation(location, to: manager)
        DiagnosticLog.step("appendSimulatedLocation 完成 lat=\(target.latitude) lon=\(target.longitude)")
        try call("flush", on: manager)
        DiagnosticLog.step("flush 完成")
        try call("startLocationSimulation", on: manager)
        DiagnosticLog.step("startLocationSimulation 完成")
        postTimezoneUpdate()
        DiagnosticLog.step("已发出时区刷新通知")

        activeTarget = target
        startedAt = Date()
    }

    /// 恢复真实定位。
    func stop() throws {
        guard let manager else {
            activeTarget = nil
            startedAt = nil
            return
        }
        DiagnosticLog.step("恢复真实定位")
        try call("stopLocationSimulation", on: manager)
        try call("clearSimulatedLocations", on: manager)
        try call("flush", on: manager)
        postTimezoneUpdate()
        activeTarget = nil
        startedAt = nil
    }

    /// 进程被系统回收前尽力清理，避免留下“幽灵定位”。
    func stopQuietly() {
        _ = try? stop()
    }
}
