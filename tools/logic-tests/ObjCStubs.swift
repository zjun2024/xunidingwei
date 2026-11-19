import Foundation

typealias CFTypeRef = AnyObject
typealias CFString = NSString
typealias CFAllocator = AnyObject
typealias CFError = AnyObject
typealias CFOptionFlags = UInt
// 与真实 SDK 一致：CFNotificationName 是可用 CFString 构造的结构体
struct CFNotificationName {
    let rawValue: CFString
    init(_ rawValue: CFString) { self.rawValue = rawValue }
}
let kCFNotificationDeliverImmediately: CFOptionFlags = 4

func CFRelease(_ obj: CFTypeRef) {}
func CFNotificationCenterGetDarwinNotifyCenter() -> OpaquePointer { OpaquePointer(bitPattern: 1)! }
func CFNotificationCenterPostNotificationWithOptions(_ c: OpaquePointer, _ n: CFNotificationName,
                                                     _ o: UnsafeRawPointer?, _ u: CFTypeRef?,
                                                     _ f: CFOptionFlags) {}

func NSSelectorFromString(_ s: String) -> String { s }

extension NSObject {
    func responds(to aSelector: String) -> Bool { true }
    func perform(_ aSelector: String) -> Unmanaged<AnyObject>? { nil }
    func perform(_ aSelector: String, with object: Any?) -> Unmanaged<AnyObject>? { nil }
}
