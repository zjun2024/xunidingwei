import Foundation
import Security

// SecTask 是 Security 的私有 SPI，与主 App 用法一致。
typealias XdwSecTaskRef = CFTypeRef
@_silgen_name("SecTaskCreateFromSelf")
func DetSecTaskCreateFromSelf(_ allocator: CFAllocator?) -> XdwSecTaskRef?
@_silgen_name("SecTaskCopyValueForEntitlement")
func DetSecTaskCopyValueForEntitlement(_ task: XdwSecTaskRef, _ entitlement: CFString, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFTypeRef?

/// 读取本进程自己的权限声明。
///
/// 检测思路：普通 App 不该有定位模拟权限。如果某个 App 声称只是「地图」，
/// 却持有 com.apple.locationd.simulation，那它本身就具备篡改定位的能力。
enum EntitlementProbe {
    static var hasLocationSimulationEntitlement: Bool? {
        guard let task = DetSecTaskCreateFromSelf(nil) else { return nil }
        guard let value = DetSecTaskCopyValueForEntitlement(
            task, "com.apple.locationd.simulation" as CFString, nil
        ) else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
