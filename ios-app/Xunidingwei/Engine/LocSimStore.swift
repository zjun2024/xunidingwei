import Combine
import Foundation
import SwiftUI
import UIKit

/// 全局状态：持有引擎、保活、历史记录，并把结果翻译成中文提示。
/// 所有读写都在主线程（SwiftUI）进行。
final class LocSimStore: ObservableObject {
    static let shared = LocSimStore()

    enum Status: Equatable {
        case idle
        case simulating(LocationTarget, since: Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published var message: String?
    @Published private(set) var history: [HistoryEntry] = []
    @Published var keepAliveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(keepAliveEnabled, forKey: Keys.keepAlive)
            applyKeepAlive()
        }
    }

    struct HistoryEntry: Codable, Identifiable, Equatable {
        var id = UUID()
        let label: String
        let latitude: Double
        let longitude: Double
        let date: Date

        var target: LocationTarget {
            LocationTarget(label: label, latitude: latitude, longitude: longitude)
        }
    }

    private enum Keys {
        static let keepAlive = "keepAliveEnabled"
        static let history = "locationHistory"
    }

    private let engine = LocSimEngine.shared
    private let keepAlive = KeepAlive()

    private init() {
        keepAliveEnabled = UserDefaults.standard.object(forKey: Keys.keepAlive) as? Bool ?? true
        loadHistory()
    }

    var activeTarget: LocationTarget? {
        if case .simulating(let target, _) = status { return target }
        return nil
    }

    var startedAt: Date? {
        if case .simulating(_, let since) = status { return since }
        return nil
    }

    var isSimulating: Bool { activeTarget != nil }

    // MARK: - 环境自检

    var entitlementOK: Bool { engine.hasSimulationEntitlement }
    var engineAvailable: Bool { engine.isClassAvailable }

    struct DiagnosticItem: Identifiable {
        let id = UUID()
        let title: String
        let ok: Bool
        let hint: String
    }

    /// 与 Windows 版 `check` 命令对应的自检项。
    func diagnostics() -> [DiagnosticItem] {
        [
            DiagnosticItem(title: "定位模拟引擎（CLSimulationManager）",
                           ok: engineAvailable,
                           hint: "只支持 iOS 15 及以上；更低版本没有这个系统组件。"),
            DiagnosticItem(title: "定位模拟权限（locationd.simulation）",
                           ok: entitlementOK,
                           hint: "必须安装本仓库打包的 ipa。用别的工具重新签名会丢掉这条权限。"),
            DiagnosticItem(title: "后台保活",
                           ok: keepAlive.isActive,
                           hint: "打开「后台保活」后，锁屏或切到其他 App 时定位才不会中断。"),
        ]
    }

    // MARK: - 主要操作

    func simulate(_ target: LocationTarget) {
        do {
            try engine.start(target)
            status = .simulating(target, since: Date())
            message = "已定位到 \(target.label)（\(target.coordinateText)）"
            record(target)
            applyKeepAlive()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            status = .failed(error.localizedDescription)
            message = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func clear() {
        do {
            try engine.stop()
            status = .idle
            message = "已恢复真实定位"
            keepAlive.stop()
        } catch {
            status = .failed(error.localizedDescription)
            message = error.localizedDescription
        }
    }

    func handleInput(_ text: String, catalog: LocationCatalog) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch trimmed.lowercased() {
        case "clear", "恢复", "取消":
            clear()
            return
        default:
            break
        }

        if let target = catalog.resolve(trimmed) {
            simulate(target)
            return
        }

        let similar = catalog.suggest(trimmed)
        if similar.isEmpty {
            message = "没找到「\(trimmed)」。可以输入国家名、城市名，或直接输入经纬度，例如 51.5074 -0.1278"
        } else {
            message = "没找到「\(trimmed)」。你是不是想找：\(similar.joined(separator: "、"))"
        }
    }

    // MARK: - 历史记录

    private func record(_ target: LocationTarget) {
        history.removeAll { $0.label == target.label }
        history.insert(HistoryEntry(label: target.label,
                                    latitude: target.latitude,
                                    longitude: target.longitude,
                                    date: Date()),
                       at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }
        persistHistory()
    }

    func removeHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Keys.history),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        history = decoded
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Keys.history)
    }

    // MARK: - 保活联动

    private func applyKeepAlive() {
        guard isSimulating else {
            keepAlive.stop()
            return
        }
        if keepAliveEnabled {
            try? keepAlive.start()
        } else {
            keepAlive.stop()
        }
    }

    /// App 回到前台时校验一次，避免定位被系统悄悄清掉。
    func refreshStatus() {
        if isSimulating {
            applyKeepAlive()
        }
    }
}
