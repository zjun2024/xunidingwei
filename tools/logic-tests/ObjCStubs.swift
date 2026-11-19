import Foundation

typealias CFTypeRef = AnyObject
typealias CFString = NSString
typealias CFAllocator = AnyObject
typealias CFError = AnyObject
typealias CFOptionFlags = UInt
let kCFNotificationDeliverImmediately: CFOptionFlags = 4

func CFRelease(_ obj: CFTypeRef) {}
func CFNotificationCenterGetDarwinNotifyCenter() -> OpaquePointer { OpaquePointer(bitPattern: 1)! }
func CFNotificationCenterPostNotificationWithOptions(_ c: OpaquePointer, _ n: CFString,
                                                     _ o: UnsafeRawPointer?, _ u: CFTypeRef?,
                                                     _ f: CFOptionFlags) {}

func NSSelectorFromString(_ s: String) -> String { s }

extension NSObject {
    func responds(to aSelector: String) -> Bool { true }
    func perform(_ aSelector: String) -> Unmanaged<AnyObject>? { nil }
    func perform(_ aSelector: String, with object: Any?) -> Unmanaged<AnyObject>? { nil }
}
