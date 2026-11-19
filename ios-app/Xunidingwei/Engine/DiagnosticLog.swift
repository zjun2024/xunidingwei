import Foundation
import os

/// 统一日志出口。
///
/// 定位模拟失败时现象是「调用成功但坐标不变」，肉眼无法区分卡在哪一步。
/// 把每一步写进系统日志后，用 pymobiledevice3 syslog 就能直接看到断点。
///
/// 抓取方式（电脑连手机）：
///   pymobiledevice3 syslog live --process-name Xunidingwei
enum DiagnosticLog {
    private static let logger = Logger(subsystem: "com.zjun2024.xunidingwei",
                                       category: "locsim")

    static func step(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func failure(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
