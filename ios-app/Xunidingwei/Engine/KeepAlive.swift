import AVFoundation
import Foundation

/// 后台保活。
///
/// 定位模拟由本进程驱动 locationd，进程一旦被系统挂起或回收，模拟就会中断。
/// 这里用「无声音频 + 后台音频权限」让 App 在锁屏、切到别的 App 之后继续运行，
/// 这是巨魔环境下定位类工具的通行做法（不显示任何提示，不产生声音）。
final class KeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false
    private var silenceBuffer: AVAudioPCMBuffer?

    var isActive: Bool { isRunning }

    private var isAttached = false

    func start() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        if !isAttached {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
                throw NSError(domain: "KeepAlive", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "无法创建音频格式"])
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else {
                throw NSError(domain: "KeepAlive", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "无法创建静音缓冲区"])
            }
            buffer.frameLength = buffer.frameCapacity
            silenceBuffer = buffer
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isAttached = true
        }

        try engine.start()
        isRunning = true
        scheduleLoop()
    }

    private func scheduleLoop() {
        guard let buffer = silenceBuffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard let strongSelf = self, strongSelf.isRunning else { return }
            DispatchQueue.main.async { strongSelf.scheduleLoop() }
        }
        if !player.isPlaying {
            player.play()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
