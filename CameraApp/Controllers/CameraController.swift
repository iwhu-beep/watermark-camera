//
//  CameraController.swift
//  CameraApp
//
//  相机控制器：管理AVCaptureSession、拍照、录像、摄像头切换、闪光灯
//  路径: CameraApp/Controllers/CameraController.swift
//

import AVFoundation
import UIKit

// MARK: - 拍照代理

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var onComplete: ((UIImage?) -> Void)?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            print("[Camera] 拍照错误: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in self?.onComplete?(nil) }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in self?.onComplete?(nil) }
            return
        }

        DispatchQueue.main.async { [weak self] in self?.onComplete?(image) }
    }
}

// MARK: - 视频数据代理

private class VideoDataDelegate: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate
{
    weak var recorder: VideoRecorder?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureVideoDataOutput {
            recorder?.appendVideoFrame(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            recorder?.appendAudioFrame(sampleBuffer)
        }
    }
}

// MARK: - 闪光灯模式

enum FlashMode: String {
    case off = "关闭"
    case on = "开启"
    case auto = "自动"

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }

    var icon: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        }
    }

    var next: FlashMode {
        switch self {
        case .auto: return .on
        case .on: return .off
        case .off: return .auto
        }
    }
}

// MARK: - 相机控制器

class CameraController: ObservableObject {

    // MARK: 公开属性

    let session = AVCaptureSession()
    var onPhotoCaptured: ((UIImage?) -> Void)?
    var onVideoRecorded: ((URL?) -> Void)?

    @Published var isReady: Bool = false
    @Published var isRecording: Bool = false
    @Published var flashMode: FlashMode = .auto
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back

    // MARK: 私有属性

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.cameraapp.session")
    private let videoQueue = DispatchQueue(label: "com.cameraapp.video")
    private let audioQueue = DispatchQueue(label: "com.cameraapp.audio")

    private var currentVideoInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?

    private var currentPhotoDelegate: PhotoCaptureDelegate?
    private let videoDelegate = VideoDataDelegate()
    private let videoRecorder = VideoRecorder()

    var watermarkProvider: (() -> String)?

    /// 字号缩放倍数
    var watermarkFontSizeScale: CGFloat = 1.0

    /// 垂直位置
    var watermarkVerticalPosition: Double = 0.15

    // MARK: - 初始化相机

    func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            print("[Camera] 配置相机...")

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // 1. 视频输入（默认后置）
            self.addVideoInput(position: .back)

            // 2. 音频输入
            self.addAudioInput()

            // 3. 照片输出
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            // 4. 视频数据输出
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self.videoDelegate, queue: self.videoQueue)
            }

            // 5. 音频数据输出
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
                self.audioOutput.setSampleBufferDelegate(self.videoDelegate, queue: self.audioQueue)
            }

            self.session.commitConfiguration()

            print("[Camera] 启动相机...")
            self.session.startRunning()

            DispatchQueue.main.async {
                self.isReady = true
                print("[Camera] 相机已就绪")
            }

            self.videoDelegate.recorder = self.videoRecorder
        }
    }

    // MARK: - 停止相机

    func stopCamera() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isReady = false }
        }
    }

    // MARK: - 切换摄像头

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRecording else {
                print("[Camera] 录像中不能切换摄像头")
                return
            }

            let newPosition: AVCaptureDevice.Position =
                self.currentCameraPosition == .back ? .front : .back

            self.session.beginConfiguration()

            // 移除旧的视频输入
            if let oldInput = self.currentVideoInput {
                self.session.removeInput(oldInput)
            }

            // 添加新的视频输入
            if self.addVideoInputInternal(position: newPosition) {
                self.currentCameraPosition = newPosition
                print("[Camera] 切换到\((newPosition == .back ? "后置" : "前置"))摄像头")
            } else {
                // 切换失败，恢复旧的
                self.addVideoInputInternal(position: self.currentCameraPosition)
                print("[Camera] 切换摄像头失败")
            }

            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - 切换闪光灯

    func cycleFlashMode() {
        flashMode = flashMode.next
        print("[Camera] 闪光灯: \(flashMode.rawValue)")
    }

    // MARK: - 拍照

    func capturePhoto() {
        guard session.isRunning else {
            print("[Camera] 相机未运行")
            onPhotoCaptured?(nil)
            return
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode.avFlashMode

        let delegate = PhotoCaptureDelegate()
        delegate.onComplete = { [weak self] image in
            self?.onPhotoCaptured?(image)
        }
        currentPhotoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    // MARK: - 开始录像

    func startRecording() {
        guard session.isRunning, !isRecording else { return }
        guard let provider = watermarkProvider else {
            print("[Camera] watermarkProvider 未设置")
            return
        }

        let size = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
        let width = size?[AVVideoWidthKey] as? Int ?? 1920
        let height = size?[AVVideoHeightKey] as? Int ?? 1080

        videoRecorder.startRecording(
            videoSize: CGSize(width: width, height: height),
            watermarkProvider: provider,
            fontSizeScale: watermarkFontSizeScale,
            verticalPosition: watermarkVerticalPosition
        ) { [weak self] url in
            self?.isRecording = false
            self?.onVideoRecorded?(url)
        }

        DispatchQueue.main.async {
            self.isRecording = true
        }
    }

    // MARK: - 停止录像

    func stopRecording() {
        guard isRecording else { return }
        videoRecorder.stopRecording { [weak self] url in
            self?.isRecording = false
            self?.onVideoRecorded?(url)
        }
    }

    // MARK: - 内部方法

    private func addVideoInput(position: AVCaptureDevice.Position) {
        guard addVideoInputInternal(position: position) else {
            print("[Camera] 无法添加视频输入")
            return
        }
    }

    private func addVideoInputInternal(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: position
        ) else { return false }

        guard let input = try? AVCaptureDeviceInput(device: device) else { return false }
        guard session.canAddInput(input) else { return false }

        session.addInput(input)
        currentVideoInput = input
        return true
    }

    private func addAudioInput() {
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        currentAudioInput = input
    }
}
