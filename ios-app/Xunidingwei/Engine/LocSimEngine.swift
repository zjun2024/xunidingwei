import CoreLocation
import Foundation
import Security

// SecTask 是 Security 框架里的私有 SPI，没有公开头文件，这里手写声明。
typealias SecTaskRef = CFTypeRef
@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> SecTaskRef?
@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(_ task: SecTaskRef, _ entitlement: CFString, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFTypeRef?

/// 定位模拟引擎。
///
/// 手机内部无法走 USB/DVT 那条路（设备不能连自己），所以这里改用 CoreLocation
/// 私有类 `CLSimulationManager`：它通过 XPC 直接驱动 locationd，需要
/// `com.apple.locationd.simulation` 权限（见 entitlements.plist）。
/// 类名不在公开头文件里，因此全部用运行时反射调用，避免链接期找不到符号。
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

    /// 让 `NSClassFromString` 拿到的类型可以直接 `init()`；
    /// 直接对 `NSObject.Type` 调 `init()` 会报 "must use a required initializer"。
    private protocol RuntimeInitializable: AnyObject {
        init()
    }

    private let classNames = ["CLSimulationManager"]
    private var manager: NSObject?

    private init() {}

    var isClassAvailable: Bool { simulationType() != nil }

    /// 运行时的权限检查：直接问内核“我这个进程有没有这条权限”。
    var hasSimulationEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        defer { CFRelease(task) }
        guard let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.locationd.simulation" as CFString, nil
        ) else { return false }
        defer { CFRelease(value) }
        return (value as? NSNumber)?.boolValue ?? false
    }

    private func simulationType() -> RuntimeInitializable.Type? {
        for name in classNames {
            if let type = NSClassFromString(name) as? RuntimeInitializable.Type {
                return type
            }
        }
        return nil
    }

    private func makeManager() throws -> NSObject {
        if let manager = manager { return manager }
        guard let type = simulationType() else { throw EngineError.classUnavailable }
        guard hasSimulationEntitlement else { throw EngineError.noEntitlement }
        guard let instance = type.init() as? NSObject else { throw EngineError.classUnavailable }
        manager = instance
        return instance
    }

    private func call(_ name: String, on object: NSObject) throws {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { throw EngineError.callFailed(name) }
        _ = object.perform(selector)
    }

    private func postTimezoneUpdate() {
        CFNotificationCenterPostNotificationWithOptions(
            CFNotificationCenterGetDarwinNotifyCenter(),
            "AutomaticTimeZoneUpdateNeeded" as CFString,
            nil, nil,
            kCFNotificationDeliverImmediately
        )
    }

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

        try call("stopLocationSimulation", on: manager)
        try call("clearSimulatedLocations", on: manager)

        let appendSelector = NSSelectorFromString("appendSimulatedLocation:")
        guard manager.responds(to: appendSelector) else { throw EngineError.callFailed("appendSimulatedLocation:") }
        _ = manager.perform(appendSelector, with: location)

        try call("flush", on: manager)
        try call("startLocationSimulation", on: manager)
        postTimezoneUpdate()

        activeTarget = target
        startedAt = Date()
    }

    /// 恢复真实定位。
    func stop() throws {
        guard let manager = manager else {
            activeTarget = nil
            startedAt = nil
            return
        }
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
