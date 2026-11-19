import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if !cond { failures += 1; print("FAIL \(msg)") }
}

let store = LocSimStore.shared
let catalog = LocationCatalog.shared

// 初始状态
expect(!store.isSimulating, "初始应为未模拟")

// 引擎在 Linux 上找不到 CLSimulationManager，模拟会失败并给出中文提示
store.simulate(LocationTarget(label: "英国 伦敦", latitude: 51.5074, longitude: -0.1278))
print("模拟结果:", store.message ?? "-")
expect(store.message?.contains("CLSimulationManager") == true, "缺少引擎时应提示 CLSimulationManager")
expect(!store.isSimulating, "失败时不应标记为模拟中")

// 解析失败提示
store.handleInput("不存在的地方", catalog: catalog)
print("未命中提示:", store.message ?? "-")
expect(store.message?.contains("没找到") == true, "应提示没找到")

// 空输入不应改变任何状态
let before = store.message
store.handleInput("   ", catalog: catalog)
expect(store.message == before, "空输入应被忽略")

// 部分输入应给出候选
store.handleInput("londo", catalog: catalog)
print("候选提示:", store.message ?? "-")
expect(store.message?.contains("伦敦") == true, "应给出伦敦候选")

// 恢复命令
store.handleInput("恢复", catalog: catalog)
print("恢复提示:", store.message ?? "-")
expect(store.message == "已恢复真实定位", "恢复命令应生效")

// 悬浮窗保活：默认关闭，且未模拟时开启也不应真的启动
let pip = PiPKeepAlive.shared
expect(store.pipEnabled == false, "悬浮窗保活默认应为关闭")
store.pipEnabled = true
expect(!pip.isRunning, "未模拟定位时不应启动画中画")
expect(pip.startedCaptions.isEmpty, "未模拟定位时不应喂入任何画面")
expect(UserDefaults.standard.object(forKey: "pipEnabled") as? Bool == true,
       "悬浮窗开关应写入 UserDefaults")
store.pipEnabled = false
expect(UserDefaults.standard.object(forKey: "pipEnabled") as? Bool == false,
       "关闭后也应写入 UserDefaults")
expect(!pip.isRunning, "关闭悬浮窗保活后应停止")

// 恢复命令也应停掉悬浮窗
store.pipEnabled = true
store.handleInput("恢复", catalog: catalog)
expect(!pip.isRunning, "恢复真实定位应停掉画中画")

// 历史记录持久化
store.clearHistory()
expect(store.history.isEmpty, "清空后历史应为空")

print(failures == 0 ? "运行时自检全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
