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
        }
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
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
}
