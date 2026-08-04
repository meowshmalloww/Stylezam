@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let rotationChanged: @MainActor (CGFloat) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.rotationChanged = rotationChanged
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.rotationChanged = rotationChanged
    }
}

final class CameraPreviewView: UIView {
    var rotationChanged: (@MainActor (CGFloat) -> Void)?
    private var lastRotationAngle: CGFloat?
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let angle = Self.rotationAngle(for: window?.windowScene?.interfaceOrientation)
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(angle)
        {
            connection.videoRotationAngle = angle
        }
        if lastRotationAngle != angle {
            lastRotationAngle = angle
            Task { @MainActor [rotationChanged] in
                rotationChanged?(angle)
            }
        }
    }

    private static func rotationAngle(for orientation: UIInterfaceOrientation?) -> CGFloat {
        switch orientation {
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .portraitUpsideDown: 270
        default: 90
        }
    }
}
