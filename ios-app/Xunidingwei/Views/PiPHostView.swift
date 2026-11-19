import AVFoundation
import SwiftUI
import UIKit

/// 把画中画的显示层挂进 SwiftUI 视图层级。
///
/// 画中画只能从「内联位置」启动，所以这一小块视图必须真的在屏幕上。
/// 它平时缩成一条细条，不干扰界面。
struct PiPHostView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> PiPContainerView {
        let view = PiPContainerView()
        view.backgroundColor = .clear
        view.hostedLayer = displayLayer
        return view
    }

    func updateUIView(_ uiView: PiPContainerView, context: Context) {
        uiView.hostedLayer = displayLayer
    }

    final class PiPContainerView: UIView {
        var hostedLayer: AVSampleBufferDisplayLayer? {
            didSet {
                guard let hostedLayer, hostedLayer.superlayer !== layer else { return }
                hostedLayer.frame = bounds
                layer.addSublayer(hostedLayer)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            hostedLayer?.frame = bounds
        }
    }
}
