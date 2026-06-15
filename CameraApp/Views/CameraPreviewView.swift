//
//  CameraPreviewView.swift
//  CameraApp
//
//  相机取景预览视图 + 水印叠加层
//  路径: CameraApp/Views/CameraPreviewView.swift
//

import AVFoundation
import SwiftUI

// MARK: - 相机预览View

/// SwiftUI相机取景器
struct CameraPreviewView: UIViewRepresentable {

    /// 绑定的AVCaptureSession
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        DispatchQueue.main.async {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            view.updatePreviewOrientation()
            view.startOrientationUpdates()
        }
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        DispatchQueue.main.async {
            uiView.updatePreviewOrientation()
        }
    }
}

// MARK: - 预览UIView子类

/// 自定义UIView，将主Layer替换为AVCaptureVideoPreviewLayer
class PreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Layer is not AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 开始监听设备方向变化
    func startOrientationUpdates() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    @objc private func orientationChanged() {
        updatePreviewOrientation()
    }

    /// 根据设备方向更新预览方向
    func updatePreviewOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else { return }

        let orientation: AVCaptureVideoOrientation
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            orientation = .landscapeRight
        case .landscapeRight:
            orientation = .landscapeLeft
        case .portraitUpsideDown:
            orientation = .portraitUpsideDown
        default:
            orientation = .portrait
        }

        connection.videoOrientation = orientation
    }
}
