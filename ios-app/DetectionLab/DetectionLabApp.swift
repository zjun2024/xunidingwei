import SwiftUI

@main
struct DetectionLabApp: App {
    @StateObject private var probe = EnvironmentProbe()

    var body: some Scene {
        WindowGroup {
            DetectorView()
                .environmentObject(probe)
        }
    }
}
