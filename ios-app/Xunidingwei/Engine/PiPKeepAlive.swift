import AVFoundation
import AVKit
import UIKit

/// 画中画悬浮窗保活。
///
/// iOS 不允许任意悬浮窗，跨 App 悬浮只有画中画这一条路。
///
/// 实现用 AVPlayer 播放一段内嵌的循环视频，而不是 AVSampleBufferDisplayLayer。
/// 原因是巨魔环境（ldid 假签名）下 CVPixelBufferCreate 申请 IOSurface 会失败，
/// 而 AVPlayer 走的是系统解码管线，不依赖 App 自己分配像素缓冲。
///
/// 视频只有 12KB，是纯色圆标，循环播放，视觉上就是静态的。
final class PiPKeepAlive: NSObject, ObservableObject {

    static let shared = PiPKeepAlive()

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// 播放器层。由 PiPHostView 挂进视图层级，画中画才能从内联位置启动。
    let playerLayer = AVPlayerLayer()

    private let player = AVPlayer()
    private var controller: AVPictureInPictureController?
    private var looper: Any?

    private override init() {
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        player.isMuted = true
        player.actionAtItemEnd = .none
    }

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - 启停

    func start() {
        guard Self.isSupported else {
            lastError = "当前系统不支持画中画"
            return
        }
        guard loadLoopVideo() else { return }

        if controller == nil {
            // 用 playerLayer 初始化器：它不需要播放代理，AVPlayer 自身即内容源。
            let pip = AVPictureInPictureController(playerLayer: playerLayer)
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            controller = pip
        }

        player.play()
        attemptStart(retries: 8)
        DiagnosticLog.step("画中画保活请求启动")
    }

    func stop() {
        controller?.stopPictureInPicture()
        player.pause()
        isRunning = false
        DiagnosticLog.step("画中画保活已停止")
    }

    /// 视频播完立即回到开头，形成无缝循环，避免系统判定「播完了」结束会话。
    private func loadLoopVideo() -> Bool {
        guard player.currentItem == nil else { return true }
        guard let url = Bundle.main.url(forResource: "pip-loop", withExtension: "mp4") else {
            report("缺少 pip-loop.mp4 资源")
            return false
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        looper = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main) { [weak self] _ in
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        return true
    }

    /// isPictureInPicturePossible 需要等内联层完成布局与首帧渲染才会变 true，
    /// 单次尝试几乎必然失败，因此按 0.25 秒间隔重试。
    private func attemptStart(retries: Int) {
        guard let controller else { return }
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            return
        }
        guard retries > 0 else {
            report("画中画无法启动，请让 App 保持在前台后重试")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.attemptStart(retries: retries - 1)
        }
    }

    /// lastError 是 @Published，重复赋相同值会无谓触发 UI 刷新。
    private func report(_ message: String) {
        guard lastError != message else { return }
        lastError = message
    }
}

// MARK: - 画中画回调

extension PiPKeepAlive: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isRunning = true
        lastError = nil
        DiagnosticLog.step("画中画已启动")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isRunning = false
        DiagnosticLog.step("画中画已结束")
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                   failedToStartPictureInPictureWithError error: Error) {
        isRunning = false
        report("画中画启动失败：\(error.localizedDescription)")
        DiagnosticLog.failure("画中画启动失败：\(error.localizedDescription)")
    }
}
