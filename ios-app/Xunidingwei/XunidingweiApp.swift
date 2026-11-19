import SwiftUI

@main
struct XunidingweiApp: App {
    @StateObject private var store = LocSimStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        DiagnosticLog.step("App 回到前台")
                        store.refreshStatus()
                    case .background:
                        DiagnosticLog.step("App 进入后台（此时模拟必须靠保活维持）")
                    case .inactive:
                        DiagnosticLog.step("App 转为非活跃")
                    @unknown default:
                        break
                    }
                }
        }
    }
}
