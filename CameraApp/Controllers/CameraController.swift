//
//  CameraController.swift
//  CameraApp
//
//  相机控制器：管理AVCaptureSession、拍照、录像
//  路径: CameraApp/Controllers/CameraController.swift
//

import AVFoundation
import UIKit

// MARK: - 拍照代理

/// AVCapturePhotoCaptureDelegate 实现
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

/// AVCaptureVideoDataOutputSampleBufferDelegate + AVCaptureAudioDataOutputSampleBufferDelegate
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

// MARK: - 相机控制器

/// 相机控制器：拍照 + 录像
class CameraController: ObservableObject {

    // MARK: 公开属性

    /// 相机会话
    let session = AVCaptureSession()

    /// 拍照完成回调
    var onPhotoCaptured: ((UIImage?) -> Void)?

    /// 录像完成回调（返回视频文件URL）
    var onVideoRecorded: ((URL?) -> Void)?

    /// 相机是否已就绪
    @Published var isReady: Bool = false

    /// 是否正在录像
    @Published var isRecording: Bool = false

    // MARK: 私有属性

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.cameraapp.session")
    private let videoQueue = DispatchQueue(label: "com.cameraapp.video")
    private let audioQueue = DispatchQueue(label: "com.cameraapp.audio")

    private var currentPhotoDelegate: PhotoCaptureDelegate?
    private let videoDelegate = VideoDataDelegate()
    private let videoRecorder = VideoRecorder()

    /// 当前水印文本（录像时传入录制器）
    var watermarkText: String = ""

    // MARK: - 初始化相机

    func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            print("[Camera] 配置相机...")

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // 1. 视频输入
            guard let videoDevice = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back
            ),
            let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
            self.session.canAddInput(videoInput) else {
                print("[Camera] 无法添加视频输入")
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(videoInput)

            // 2. 音频输入
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }

            // 3. 照片输出
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            // 4. 视频数据输出（用于录像）
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

            // 关联录制器
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

    // MARK: - 拍照

    func capturePhoto() {
        guard session.isRunning else {
            print("[Camera] 相机未运行")
            onPhotoCaptured?(nil)
            return
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto

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

        let size = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
        let width = size?[AVVideoWidthKey] as? Int ?? 1920
        let height = size?[AVVideoHeightKey] as? Int ?? 1080

        videoRecorder.startRecording(
            videoSize: CGSize(width: width, height: height),
            watermarkText: watermarkText
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

    // MARK: - 获取视频尺寸

    /// 获取当前视频输出尺寸
    func videoSize() -> CGSize {
        let settings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
        let w = settings?[AVVideoWidthKey] as? Int ?? 1920
        let h = settings?[AVVideoHeightKey] as? Int ?? 1080
        return CGSize(width: w, height: h)
    }
}
