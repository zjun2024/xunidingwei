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
                    if phase == .active {
                        store.refreshStatus()
                    }
                }
        }
    }
}
