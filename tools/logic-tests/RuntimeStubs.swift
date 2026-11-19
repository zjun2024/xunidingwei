import Foundation

final class UINotificationFeedbackGenerator {
    enum FeedbackType { case success, error, warning }
    init() {}
    func notificationOccurred(_ t: FeedbackType) {}
}

final class KeepAlive {
    var isActive: Bool { false }
    func start() throws {}
    func stop() {}
}

// SecTask 在 Linux 上不存在，提供同名符号供链接
func SecTaskCreateFromSelf(_ a: CFAllocator?) -> CFTypeRef? { nil }
func SecTaskCopyValueForEntitlement(_ t: CFTypeRef, _ e: CFString,
                                    _ err: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFTypeRef? { nil }
