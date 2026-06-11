//
//  CameraController.swift
//  CameraApp
//
//  相机控制器：管理AVCaptureSession、取景预览、拍照
//  路径: CameraApp/Controllers/CameraController.swift
//

import AVFoundation
import UIKit

// MARK: - 拍照代理

/// AVCapturePhotoCaptureDelegate 实现，处理拍照回调
private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    /// 拍照完成回调
    var onComplete: ((UIImage?) -> Void)?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            print("[CameraController] 拍照错误: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onComplete?(nil)
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("[CameraController] 无法从拍照数据生成UIImage")
            DispatchQueue.main.async { [weak self] in
                self?.onComplete?(nil)
            }
            return
        }

        // 回调切到主线程，便于UI层直接处理
        DispatchQueue.main.async { [weak self] in
            self?.onComplete?(image)
        }
    }
}

// MARK: - 相机控制器

/// 相机控制器：封装AVCaptureSession，提供预览和拍照能力
class CameraController: ObservableObject {

    // MARK: 公开属性

    /// 相机会话，供CameraPreviewView绑定
    let session = AVCaptureSession()

    /// 拍照完成回调
    var onPhotoCaptured: ((UIImage?) -> Void)?
    
    /// 相机是否已就绪
    @Published var isReady: Bool = false

    // MARK: 私有属性

    /// 照片输出
    private let photoOutput = AVCapturePhotoOutput()

    /// 会话队列，避免阻塞主线程
    private let sessionQueue = DispatchQueue(label: "com.cameraapp.sessionQueue")

    /// 当前拍照代理（需强引用防止被释放）
    private var currentDelegate: PhotoCaptureDelegate?

    // MARK: - 初始化相机

    /// 配置并启动相机会话
    func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            print("[CameraController] 开始配置相机...")
            
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // 1. 添加视频输入（后置广角摄像头）
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ) else {
                print("[CameraController] 无法获取后置摄像头设备")
                self.session.commitConfiguration()
                return
            }

            guard let input = try? AVCaptureDeviceInput(device: device) else {
                print("[CameraController] 无法创建摄像头输入")
                self.session.commitConfiguration()
                return
            }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            // 2. 添加照片输出
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()
            
            print("[CameraController] 启动相机...")
            self.session.startRunning()
            
            // 标记相机已就绪
            DispatchQueue.main.async {
                self.isReady = true
                print("[CameraController] 相机已就绪")
            }
        }
    }

    // MARK: - 停止相机

    /// 停止相机会话
    func stopCamera() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isReady = false
            }
        }
    }

    // MARK: - 拍照

    /// 触发拍照，结果通过 onPhotoCaptured 回调返回
    func capturePhoto() {
        guard session.isRunning else {
            print("[CameraController] 相机未运行，无法拍照")
            onPhotoCaptured?(nil)
            return
        }
        
        print("[CameraController] 开始拍照...")
        
        let settings = AVCapturePhotoSettings()
        // 禁用闪光灯以获得更自然的照片
        settings.flashMode = .off

        let delegate = PhotoCaptureDelegate()
        delegate.onComplete = { [weak self] image in
            print("[CameraController] 拍照完成，图像: \(image != nil ? "成功" : "失败")")
            self?.onPhotoCaptured?(image)
        }

        // 强引用代理，直到回调完成
        currentDelegate = delegate

        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}
