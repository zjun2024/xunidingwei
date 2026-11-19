import AVFoundation
import AVKit
import UIKit

/// 画中画悬浮窗保活。
///
/// iOS 不允许任意悬浮窗，跨 App 悬浮只有画中画这一条路。所以这里用
/// AVSampleBufferDisplayLayer 作为画中画内容源：悬浮窗里显示当前模拟坐标，
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
    private var caption = "寻定位"

    private let bufferSize = CGSize(width: 480, height: 270)
    private var frameIndex: Int64 = 0

    private override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
    }

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - 启停

    /// - Parameter caption: 悬浮窗上显示的文字，通常是「城市 + 坐标」。
    func start(caption text: String) {
        guard Self.isSupported else {
            lastError = "当前系统不支持画中画"
            return
        }
        caption = text

        if controller == nil {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self)
            let pip = AVPictureInPictureController(contentSource: source)
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            controller = pip
        }

        startFeeding()

        guard let controller else { return }
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            // 内联层还没进入可见视图时无法立即启动，等一个渲染周期再试。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let controller = self.controller else { return }
                if controller.isPictureInPicturePossible {
                    controller.startPictureInPicture()
                } else {
                    self.lastError = "画中画暂时无法启动，请保持 App 在前台再点一次"
                }
            }
        }
        DiagnosticLog.step("画中画保活请求启动：\(text)")
    }

    func stop() {
        feeder?.invalidate()
        feeder = nil
        controller?.stopPictureInPicture()
        isRunning = false
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
        guard let buffer = makePixelBuffer() else { return }
        guard let sample = makeSampleBuffer(from: buffer) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
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

        frameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 1),
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
        let attrs: [CFString: Any] = [
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

        draw(caption: caption, in: context, size: bufferSize)
        return pixelBuffer
    }

    private func draw(caption: String, in context: CGContext, size: CGSize) {
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let lines = caption.components(separatedBy: "\n")
        let title = lines.first ?? caption
        let detail = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : ""

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .regular),
            .foregroundColor: UIColor(white: 0.75, alpha: 1),
        ]

        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let detailSize = detail.isEmpty ? .zero : (detail as NSString).size(withAttributes: detailAttrs)

        let totalHeight = titleSize.height + (detail.isEmpty ? 0 : detailSize.height + 6)
        var y = (size.height - totalHeight) / 2

        (title as NSString).draw(
            at: CGPoint(x: (size.width - titleSize.width) / 2, y: y),
            withAttributes: titleAttrs)
        y += titleSize.height + 6

        if !detail.isEmpty {
            (detail as NSString).draw(
                at: CGPoint(x: (size.width - detailSize.width) / 2, y: y),
                withAttributes: detailAttrs)
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
