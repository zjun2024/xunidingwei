import SwiftUI

/// 靶场界面：显示当前坐标与全部检测结果。
struct DetectorView: View {
    @EnvironmentObject private var probe: EnvironmentProbe

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("当前定位")) {
                    Text(probe.latestText)
                        .font(.system(.body, design: .monospaced))
                    Text("已采集 \(probe.samples.count) 个样本")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("重新采集") {
                        probe.evaluate()
                    }
                }

                Section(header: Text("检测结论")) {
                    let severity = TamperDetector.overallSeverity(probe.findings)
                    HStack {
                        Image(systemName: iconName(severity))
                            .foregroundColor(color(severity))
                        Text(TamperDetector.summary(probe.findings))
                    }
                    .font(.callout)
                }

                Section(header: Text("检测明细")) {
                    if probe.findings.isEmpty {
                        Text("没有触发任何规则。")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(probe.findings) { finding in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(finding.severity.label)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(color(finding.severity).opacity(0.15))
                                        .foregroundColor(color(finding.severity))
                                        .cornerRadius(4)
                                    Text(finding.title)
                                        .font(.callout)
                                }
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section(header: Text("说明")) {
                    Text("本 App 只做检测，不修改任何定位。用它配合定位模拟工具，可以观察哪些特征会被识别出来。")
                        .font(.footnote)
                }
            }
            .navigationTitle("定位检测靶场")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                probe.requestAuthorization()
                probe.startSampling()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func iconName(_ severity: Severity) -> String {
        switch severity {
        case .danger: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ severity: Severity) -> Color {
        switch severity {
        case .danger: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
