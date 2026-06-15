//
//  VideoRecorder.swift
//  CameraApp
//
//  视频录制器：使用 AVAssetWriter 录制视频并实时叠加水印
//  路径: CameraApp/Utilities/VideoRecorder.swift
//

import AVFoundation
import CoreImage
import UIKit

// MARK: - 视频录制器

/// 实时水印视频录制器
///
/// 用法：
/// ```swift
/// let recorder = VideoRecorder()
/// recorder.startRecording(watermarkText: "经度: 116.4\n纬度: 39.9")
/// // ... 传入视频帧和音频数据 ...
/// recorder.stopRecording { url in
///     print("视频已保存到: \(url)")
/// }
/// ```
final class VideoRecorder: NSObject {

    // MARK: - 公开属性

    /// 是否正在录制
    var isRecording: Bool = false

    // MARK: - 私有属性

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var videoFrameCount: Int64 = 0
    private var startTime: CMTime = .zero
    private var videoSize: CGSize = .zero

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let recordingQueue = DispatchQueue(label: "com.cameraapp.videorecorder")

    /// 录制完成回调
    private var completion: ((URL?) -> Void)?

    /// 输出文件路径
    private var outputURL: URL?

    /// 当前水印文本
    private var watermarkText: String = ""
    
    /// 动态水印文本提供者（每帧调用）
    private var watermarkProvider: (() -> String)?

    /// 字号缩放倍数
    private var fontSizeScale: CGFloat = 1.0

    /// 垂直位置（0=底部, 0.5=居中, 1=顶部）
    private var verticalPosition: Double = 0.15

    // MARK: - 开始录制

    /// 开始录制视频
    ///
    /// - Parameters:
    ///   - outputURL: 输出文件路径（默认临时目录）
    ///   - videoSize: 视频尺寸
    ///   - watermarkText: 水印文本
    ///   - completion: 完成回调，返回文件URL
    func startRecording(
        outputURL: URL? = nil,
        videoSize: CGSize,
        watermarkProvider: @escaping () -> String,
        fontSizeScale: CGFloat = 1.0,
        verticalPosition: Double = 0.15,
        completion: @escaping (URL?) -> Void
    ) {
        guard !isRecording else { return }

        self.completion = completion
        self.videoSize = videoSize
        self.watermarkProvider = watermarkProvider
        self.watermarkText = watermarkProvider()
        self.fontSizeScale = fontSizeScale
        self.verticalPosition = verticalPosition
        self.videoFrameCount = 0
        self.startTime = .zero

        // 输出路径
        let url: URL
        if let outputURL = outputURL {
            url = outputURL
        } else {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "VID_\(timestampString()).mp4"
            url = tempDir.appendingPathComponent(fileName)
        }

        // 删除已存在的文件
        try? FileManager.default.removeItem(at: url)
        self.outputURL = url

        do {
            // 创建 AVAssetWriter
            assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)

            // 视频配置
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoSize.width),
                AVVideoHeightKey: Int(videoSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]

            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true

            // 像素缓冲适配器
            let sourceAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height)
            ]
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: sourceAttributes
            )

            // 音频配置
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true

            // 添加输入
            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)
            }
            if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                assetWriter?.add(audioInput)
            }

            // 开始写入
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: .zero)

            isRecording = true
            print("[VideoRecorder] 开始录制: \(url.lastPathComponent)")

        } catch {
            print("[VideoRecorder] 初始化失败: \(error)")
            self.completion?(nil)
        }
    }

    // MARK: - 写入视频帧

    /// 写入一帧视频数据（带水印叠加）
    ///
    /// - Parameter sampleBuffer: 原始视频帧
    func appendVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData else { return }

        let rawTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if videoFrameCount == 0 {
            startTime = rawTimestamp
        }

        // 将绝对时间戳转换为相对时间戳（从0开始）
        let relativeTime = CMTimeSubtract(rawTimestamp, startTime)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 每帧动态获取水印文本（更新时间等）
        let currentWatermark = watermarkProvider?() ?? watermarkText
        // 在原始帧上叠加水印
        renderWatermark(on: pixelBuffer, text: currentWatermark)
        adaptor?.append(pixelBuffer, withPresentationTime: relativeTime)
        videoFrameCount += 1
    }

    // MARK: - 写入音频帧

    /// 写入一帧音频数据
    ///
    /// - Parameter sampleBuffer: 音频数据
    func appendAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let audioInput = audioInput,
              audioInput.isReadyForMoreMediaData else { return }

        // 将音频时间戳也转换为相对时间
        guard startTime != .zero else { return } // 等待第一帧视频设定基准
        let rawTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let relativeTime = CMTimeSubtract(rawTimestamp, startTime)

        // 创建新的 sampleBuffer 使用相对时间戳
        if let adjustedBuffer = adjustedSampleBuffer(sampleBuffer, presentationTime: relativeTime) {
            audioInput.append(adjustedBuffer)
        }
    }

    /// 创建调整时间戳后的 CMSampleBuffer 副本
    private func adjustedSampleBuffer(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var adjustedTiming = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var outputBuffer: CMSampleBuffer?
        let count = CMSampleBufferGetNumSamples(sampleBuffer)

        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &adjustedTiming,
            sampleBufferOut: &outputBuffer
        ) == noErr else { return nil }

        return outputBuffer
    }

    // MARK: - 停止录制

    /// 停止录制
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        isRecording = false
        self.completion = completion

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        assetWriter?.finishWriting { [weak self] in
            guard let self = self else { return }
            let url = self.outputURL
            print("[VideoRecorder] 录制完成: \(url?.lastPathComponent ?? "nil")")
            DispatchQueue.main.async {
                self.completion?(url)
            }
        }
    }

    // MARK: - 水印渲染

    /// 在像素缓冲区上渲染水印文本
    private func renderWatermark(on pixelBuffer: CVPixelBuffer, text: String) {
        guard !text.isEmpty else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: width, height: height)

        // 从 pixelBuffer 创建 CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 创建水印文字图层
        // 基准字号：根据视频宽度计算，再乘以用户设置的倍数
        let baseFontSize = max(14, CGFloat(width) / 40)
        let fontSize = baseFontSize * fontSizeScale

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = UIFont.boldSystemFont(ofSize: fontSize)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOffset = CGSize(width: 1, height: 1)
        textLayer.shadowOpacity = 0.8
        textLayer.shadowRadius = 2
        textLayer.alignmentMode = .left
        textLayer.isWrapped = true

        // 计算文字尺寸
        let padding: CGFloat = max(10, CGFloat(width) / 80)
        let maxWidth = size.width - padding * 2
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: UIFont.boldSystemFont(ofSize: fontSize)],
            context: nil
        ).size

        // 根据 verticalPosition 计算Y坐标
        // 0 = 底部（margin上方），0.5 = 居中，1 = 顶部
        let bottomMargin = padding + textSize.height + 10
        let availableSpace = size.height - bottomMargin - padding
        let yPos = padding + availableSpace * CGFloat(1.0 - verticalPosition)

        textLayer.frame = CGRect(
            x: padding,
            y: yPos,
            width: maxWidth,
            height: textSize.height + 10
        )

        // 创建合成图层
        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: size)
        rootLayer.addSublayer(textLayer)

        // 渲染水印图层
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return
        }
        rootLayer.render(in: ctx)
        guard let watermarkImage = ctx.makeImage() else {
            UIGraphicsEndImageContext()
            return
        }
        UIGraphicsEndImageContext()

        let watermarkCI = CIImage(cgImage: watermarkImage)

        // 合成：水印在上，原始图像在下
        let compositor = CIFilter(name: "CISourceOverCompositing")
        compositor?.setValue(watermarkCI, forKey: kCIInputImageKey)
        compositor?.setValue(ciImage, forKey: kCIInputBackgroundImageKey)

        guard let outputImage = compositor?.outputImage else { return }

        // 写回像素缓冲区
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        ciContext.render(outputImage, to: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    // MARK: - 工具方法

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
