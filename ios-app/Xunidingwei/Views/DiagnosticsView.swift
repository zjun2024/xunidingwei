import SwiftUI

/// 环境自检，对应 Windows 版 ios_loc.py 的 check / setup 说明。
struct DiagnosticsView: View {
    @EnvironmentObject private var store: LocSimStore
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("自检")) {
                    ForEach(store.diagnostics()) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(item.ok ? Color.green : Color.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                if !item.ok {
                                    Text(item.hint)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("开发者模式（iOS 16 及以上）")) {
                    Text("如果模拟不生效，先在 设置 → 隐私与安全性 → 开发者模式 里打开开关，按提示重启手机，再回来试。")
                        .font(.footnote)
                }

                Section(header: Text("定位服务")) {
                    Text("确认 设置 → 隐私与安全性 → 定位服务 是打开的，否则系统不会采用模拟坐标。")
                        .font(.footnote)
                }

                Section(header: Text("关于权限")) {
                    Text("本 App 依赖 com.apple.locationd.simulation 权限。请安装仓库打包的 ipa；用其他工具重新签名会丢掉这条权限，定位就会失效。")
                        .font(.footnote)
                }
            }
            .navigationTitle("环境自检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
