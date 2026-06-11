//
//  CameraPreviewView.swift
//  CameraApp
//
//  相机取景预览视图：UIViewRepresentable封装AVCaptureVideoPreviewLayer
//  路径: CameraApp/Views/CameraPreviewView.swift
//

import AVFoundation
import SwiftUI

// MARK: - 相机预览View

/// SwiftUI相机取景器，承载AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {

    /// 绑定的AVCaptureSession
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        // 延迟设置session，确保view已完全初始化
        DispatchQueue.main.async {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
        }
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // session变更时自动由PreviewLayer接管，无需额外处理
    }
}

// MARK: - 预览UIView子类

/// 自定义UIView，将主Layer替换为AVCaptureVideoPreviewLayer
/// 这样PreviewLayer会自动跟随View的frame变化而调整
class PreviewView: UIView {

    /// 将UIView的默认CALayer替换为AVCaptureVideoPreviewLayer
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    /// 便捷访问PreviewLayer
    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Layer is not AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
