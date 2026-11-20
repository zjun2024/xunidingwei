import AVFoundation
import AVKit
import UIKit

/// 画中画悬浮窗保活。
///
/// iOS 不允许任意悬浮窗，跨 App 悬浮只有画中画这一条路。所以这里用
/// AVSampleBufferDisplayLayer 作为画中画内容源：悬浮窗里显示一个圆形定位图标，
/// 同时因为画中画会话活跃，App 不会在切到后台后被挂起。
///
/// 与 KeepAlive（无声音频）的区别：音频保活没有界面反馈，用户不知道还在不在；
/// 画中画保活看得见，且能直接确认进程还活着。
final class PiPKeepAlive: NSObject, ObservableObject {

    static let shared = PiPKeepAlive()

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// 画中画内容层。由 PiPHostView 挂进视图层级，画中画才能从内联位置启动。
    let displayLayer = AVSampleBufferDisplayLayer()

    private var controller: AVPictureInPictureController?
    private var feeder: Timer?
    private var formatDescription: CMVideoFormatDescription?
    /// AVSampleBufferDisplayLayer 靠 timebase 决定何时显示帧。
    /// 不设置它，入队的帧永远不会渲染，画中画就是一片黑。
    private var timebase: CMTimebase?
    /// 内联层必须始终可见，否则系统判定不可用、画中画拉不起来。
    /// 因此空闲时也画一帧灰圆，运行时再切成绿圆。
    private var active = false

    /// 画中画窗口的尺寸由系统按画面宽高比决定，App 无法直接指定。
    /// 用正方形画布能让窗口收到最小，内容再画成圆形即可。
    private let bufferSize = CGSize(width: 400, height: 400)

    private override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        setUpTimebase()
        enqueueFrame()
    }

    /// 用主机时钟作为时间源，并让它以 1.0 速率前进，
    /// 这样以「当前时刻」为 PTS 的帧会被立即显示。
    private func setUpTimebase() {
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &tb)
        guard let tb else { return }
        CMTimebaseSetTime(tb, time: CMClockGetTime(CMClockGetHostTimeClock()))
        CMTimebaseSetRate(tb, rate: 1.0)
        displayLayer.controlTimebase = tb
        timebase = tb
    }

    /// lastError 是 @Published，每秒渲染都会调用 enqueueFrame，
    /// 直接赋值会不断触发 UI 刷新，所以只在内容变化时更新。
    private func report(_ message: String) {
        guard lastError != message else { return }
        lastError = message
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
        if controller == nil {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self)
            let pip = AVPictureInPictureController(contentSource: source)
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            controller = pip
        }

        active = true
        startFeeding()

        attemptStart(retries: 8)
        DiagnosticLog.step("画中画保活请求启动")
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

    func stop() {
        feeder?.invalidate()
        feeder = nil
        controller?.stopPictureInPicture()
        isRunning = false
        active = false
        enqueueFrame()
        DiagnosticLog.step("画中画保活已停止")
    }

    // MARK: - 喂帧

    /// 画中画会话需要持续有新帧，否则会被系统判定为空闲而结束。
    private func startFeeding() {
        feeder?.invalidate()
        enqueueFrame()
        feeder = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.enqueueFrame()
        }
    }

    private func enqueueFrame() {
        if displayLayer.status == .failed {
            // 失败原因必须暴露出来，否则用户只看到黑屏、无从判断。
            let reason = displayLayer.error?.localizedDescription ?? "未知原因"
            report("画面渲染失败：\(reason)")
            DiagnosticLog.failure("画中画渲染失败：\(reason)")
            displayLayer.flush()
        }
        guard let buffer = makePixelBuffer() else {
            report("无法创建像素缓冲")
            return
        }
        guard let sample = makeSampleBuffer(from: buffer) else {
            report("无法创建样本缓冲")
            return
        }
        displayLayer.enqueue(sample)
    }

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return nil }

        // PTS 必须取自与 timebase 同一时钟，否则帧不会被判定为「到时间了」。
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid)

        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sample)
        return sample
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        let width = Int(bufferSize.width)
        let height = Int(bufferSize.height)
        // IOSurface 支撑是 AVSampleBufferDisplayLayer 渲染的前提，缺了它画面全黑。
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: base, width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        draw(in: context, size: bufferSize)
        return pixelBuffer
    }

    /// 画一个纯圆形徽标：深色底 + 绿色描边 + 中央定位图标，不带文字。
    /// 画布必须不透明，圆以外的区域填同色，视觉上仍是一个圆。
    private func draw(in context: CGContext, size: CGSize) {
        // 画中画不支持透明合成，透明区域会被渲染成黑色。
        // 因此整幅画布先填满圆底同色，再画圆，避免出现黑色方框。
        context.setFillColor(UIColor(white: 0.09, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 * 0.78

        // 运行时绿色，空闲时灰色，与 App 内状态配色一致
        context.setStrokeColor((active ? UIColor.systemGreen : UIColor(white: 0.35, alpha: 1)).cgColor)
        context.setLineWidth(10)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                         width: radius * 2, height: radius * 2))

        // 只留定位图标，居中显示。
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: radius * 0.95, weight: .semibold)
        let tint = active ? UIColor.white : UIColor(white: 0.6, alpha: 1)
        if let icon = UIImage(systemName: "location.fill", withConfiguration: symbolConfig)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) {
            let iconSize = icon.size
            icon.draw(at: CGPoint(x: center.x - iconSize.width / 2,
                                  y: center.y - iconSize.height / 2))
        }
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
        feeder?.invalidate()
        feeder = nil
        DiagnosticLog.step("画中画已结束")
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                   failedToStartPictureInPictureWithError error: Error) {
        isRunning = false
        lastError = "画中画启动失败：\(error.localizedDescription)"
        DiagnosticLog.failure("画中画启动失败：\(error.localizedDescription)")
    }
}

// MARK: - 播放代理

extension PiPKeepAlive: AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                   setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController) -> CMTimeRange {
        // 无限时长，避免系统按「播完了」结束会话。
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                   didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                   skipByInterval skipInterval: CMTime,
                                   completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
