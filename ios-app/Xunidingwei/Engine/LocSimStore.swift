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

    /// 悬浮窗保活（画中画）。iOS 上跨 App 悬浮只有画中画这一条路，
    /// 它同时也是最稳的后台保活方式：会话活跃时进程不会被挂起。
    @Published var pipEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pipEnabled, forKey: Keys.pip)
            applyPiP()
        }
    }

    @Published private(set) var pipError: String?

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
        static let pip = "pipEnabled"
        static let history = "locationHistory"
    }

    private let engine = LocSimEngine.shared
    private let keepAlive = KeepAlive()
    private let pip = PiPKeepAlive.shared

    private init() {
        keepAliveEnabled = UserDefaults.standard.object(forKey: Keys.keepAlive) as? Bool ?? true
        pipEnabled = UserDefaults.standard.object(forKey: Keys.pip) as? Bool ?? false
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

    struct DiagnosticItem: Identifiable {
        let id = UUID()
        let title: String
        let ok: Bool
        let hint: String
    }

    /// 与 Windows 版 `check` 命令对应的自检项。
    ///
    /// 第一项分两级：类不存在，或类存在但缺少关键方法。
    /// 两者提示不同，便于定位是系统版本问题还是私有 API 变动。
    func diagnostics() -> [DiagnosticItem] {
        let hasClass = engine.isClassAvailable
        let hasInterface = hasClass && engine.isInterfaceComplete
        let engineHint: String
        if !hasClass {
            engineHint = "系统里没有 CLSimulationManager 这个类，说明当前系统版本不支持这条通道。"
        } else if !hasInterface {
            engineHint = "找到 CLSimulationManager，但缺少模拟所需的方法，可能是系统版本改了私有接口。"
        } else {
            engineHint = "系统组件与所需方法都在。"
        }

        return [
            DiagnosticItem(title: "定位模拟引擎（CLSimulationManager）",
                           ok: hasInterface,
                           hint: engineHint),
            DiagnosticItem(title: "定位模拟权限（locationd.simulation）",
                           ok: entitlementOK,
                           hint: "必须安装本仓库打包的 ipa。用别的工具重新签名会丢掉这条权限。"),
            DiagnosticItem(title: "后台保活",
                           ok: keepAlive.isActive,
                           hint: "保活只在定位进行中启动；未开始定位时这一项为空是正常的。"),
            DiagnosticItem(title: "悬浮窗保活（画中画）",
                           ok: PiPKeepAlive.isSupported,
                           hint: "iOS 的跨 App 悬浮只有画中画一种形式。系统不支持时这一项会失败，可继续用上面的后台保活。"),
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
            applyPiP()
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
            pip.stop()
            pipError = nil
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
            do {
                try keepAlive.start()
            } catch {
                DiagnosticLog.failure("保活启动失败：\(error.localizedDescription)")
            }
        } else {
            keepAlive.stop()
        }
    }

    /// 悬浮窗保活的联动逻辑，与 applyKeepAlive 平行。
    private func applyPiP() {
        guard isSimulating else {
            pip.stop()
            pipError = nil
            return
        }
        guard pipEnabled else {
            pip.stop()
            pipError = nil
            return
        }
        pip.start()
        pipError = pip.lastError
    }

    /// App 回到前台时校验一次，避免定位被系统悄悄清掉。
    func refreshStatus() {
        if isSimulating {
            applyKeepAlive()
        }
    }
}
