import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LocSimStore
    @State private var input = ""
    @State private var showCatalog = false
    @State private var showDiagnostics = false

    private let catalog = LocationCatalog.shared

    var body: some View {
        NavigationView {
            List {
                statusSection
                inputSection
                quickSection
                if !store.history.isEmpty {
                    historySection
                }
                aboutSection
            }
            .navigationTitle("寻定位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCatalog = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("地点列表")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showDiagnostics = true
                    } label: {
                        Image(systemName: "stethoscope")
                    }
                    .accessibilityLabel("环境自检")
                }
            }
            .sheet(isPresented: $showCatalog) {
                CatalogView { place in
                    store.simulate(LocationTarget(label: place.label,
                                                  latitude: place.latitude,
                                                  longitude: place.longitude))
                    showCatalog = false
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .alert(isPresented: Binding(
                get: { store.message != nil },
                set: { if !$0 { store.message = nil } }
            )) {
                Alert(title: Text("提示"),
                      message: Text(store.message ?? ""),
                      dismissButton: .default(Text("好")) { store.message = nil })
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 当前状态

    private var statusSection: some View {
        Section(header: Text("状态")) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(store.isSimulating ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: store.isSimulating ? "location.fill" : "location.slash")
                        .font(.title3)
                        .foregroundColor(store.isSimulating ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isSimulating ? "正在模拟定位" : "当前是真实定位")
                        .font(.headline)
                    if let target = store.activeTarget {
                        Text(target.label)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(target.coordinateText)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    } else {
                        Text("选一个地点即可开始")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            if store.isSimulating {
                if let since = store.startedAt {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        HStack {
                            Text("已持续")
                            Spacer()
                            Text(Self.elapsedText(from: since, to: context.date))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                Toggle("后台保活", isOn: Binding(
                    get: { store.keepAliveEnabled },
                    set: { store.keepAliveEnabled = $0 }
                ))
                Button {
                    store.clear()
                } label: {
                    Label("恢复真实定位", systemImage: "arrow.uturn.backward")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private static func elapsedText(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours) 时 \(minutes) 分 \(seconds) 秒" }
        if minutes > 0 { return "\(minutes) 分 \(seconds) 秒" }
        return "\(seconds) 秒"
    }

    // MARK: - 输入

    private var inputSection: some View {
        Section(header: Text("输入"),
                footer: Text("例如：英国 / 洛杉矶 / 美国洛杉矶 / 东京 / 51.5074 -0.1278")) {
            HStack {
                TextField("国家 / 城市 / 经纬度", text: $input)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.go)
                    .onSubmit(submit)
                Button("定位", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func submit() {
        store.handleInput(input, catalog: catalog)
        input = ""
    }

    // MARK: - 快捷入口

    private var quickSection: some View {
        Section(header: Text("快捷")) {
            Button {
                showCatalog = true
            } label: {
                Label("浏览全部地点（\(LocationData.places.count) 个城市）", systemImage: "globe.asia.australia")
            }
            Button {
                showDiagnostics = true
            } label: {
                Label("环境自检", systemImage: "checkmark.shield")
            }
        }
    }

    // MARK: - 历史

    private var historySection: some View {
        Section(header: HStack {
            Text("最近使用")
            Spacer()
            Button("清空") { store.clearHistory() }
                .font(.caption)
                .textCase(nil)
        }) {
            ForEach(store.history) { entry in
                Button {
                    store.simulate(entry.target)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label).foregroundColor(.primary)
                        Text(entry.target.coordinateText)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete(perform: store.removeHistory)
        }
    }

    // MARK: - 说明

    private var aboutSection: some View {
        Section(header: Text("说明")) {
            Text("定位在本 App 运行期间保持有效。退出 App 或点「恢复真实定位」即恢复。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
