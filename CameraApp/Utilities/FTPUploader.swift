//
//  FTPUploader.swift
//  CameraApp
//
//  FTP 文件上传工具类，使用 URLSession + CFWriteStream
//  路径: CameraApp/Utilities/FTPUploader.swift
//

import Foundation
import UIKit

// MARK: - FTP 配置

/// FTP 服务器配置
struct FTPConfig {
    /// 服务器地址（如 ftp.example.com）
    static var host: String = ""
    /// 端口（默认21）
    static var port: Int = 21
    /// 用户名
    static var username: String = ""
    /// 密码
    static var password: String = ""
    /// 远程目录（如 /photos/）
    static var remoteDir: String = "/"
}

// MARK: - FTP 上传错误

enum FTPUploadError: Error, LocalizedError {
    case notConfigured
    case fileReadFailed
    case connectionFailed(String)
    case uploadFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置 FTP 服务器信息"
        case .fileReadFailed:
            return "读取本地文件失败"
        case .connectionFailed(let msg):
            return "FTP 连接失败: \(msg)"
        case .uploadFailed(let msg):
            return "FTP 上传失败: \(msg)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - FTP 上传工具类

/// FTP 文件上传工具（单例）
///
/// 用法示例：
/// ```swift
/// FTPConfig.host = "ftp.example.com"
/// FTPConfig.port = 21
/// FTPConfig.username = "user"
/// FTPConfig.password = "pass"
/// FTPConfig.remoteDir = "/photos/"
///
/// FTPUploader.shared.uploadFile(
///     localURL: fileURL,
///     onSuccess: { print("上传成功") },
///     onFailure: { error in print("失败: \(error)") }
/// )
/// ```
final class FTPUploader {

    static let shared = FTPUploader()
    private init() {}

    // MARK: - 上传本地文件

    /// 上传本地文件到 FTP 服务器
    ///
    /// - Parameters:
    ///   - localURL: 本地文件URL
    ///   - onProgress: 进度回调（0.0~1.0），主线程
    ///   - onSuccess: 成功回调，主线程
    ///   - onFailure: 失败回调，主线程
    func uploadFile(
        localURL: URL,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (FTPUploadError) -> Void
    ) {
        // 配置校验
        guard !FTPConfig.host.isEmpty else {
            deliverFailure(onFailure, error: .notConfigured)
            return
        }

        // 读取文件数据
        guard let fileData = try? Data(contentsOf: localURL) else {
            deliverFailure(onFailure, error: .fileReadFailed)
            return
        }

        let fileName = localURL.lastPathComponent
        let remotePath = buildRemotePath(fileName: fileName)

        // 构建 FTP URL
        guard let ftpURL = URL(string: remotePath) else {
            deliverFailure(onFailure, error: .connectionFailed("无效的 FTP URL"))
            return
        }

        print("[FTPUploader] 上传到: \(remotePath)")

        // 使用 InputStream + CFWriteStream 上传
        let inputStream = InputStream(data: fileData)
        inputStream.open()

        guard let writeStream = CFWriteStreamCreateWithFTPURL(
            kCFAllocatorDefault,
            ftpURL as CFURL
        ) else {
            deliverFailure(onFailure, error: .connectionFailed("无法创建 FTP 写入流"))
            inputStream.close()
            return
        }

        // 设置用户名和密码
        CFWriteStreamSetProperty(
            writeStream,
            .ftpUserName,
            FTPConfig.username as CFString
        )
        CFWriteStreamSetProperty(
            writeStream,
            .ftpPassword,
            FTPConfig.password as CFString
        )
        // 使用被动模式
        CFWriteStreamSetProperty(
            writeStream,
            .ftpUsePassiveMode,
            kCFBooleanTrue
        )

        let totalBytes = fileData.count
        var uploadedBytes = 0
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        writeStream.open()

        // 后台线程执行上传
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                writeStream.close()
                inputStream.close()
            }

            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
                if bytesRead < 0 {
                    let error = inputStream.streamError
                    self.deliverFailure(onFailure, error: .networkError(error ?? NSError(domain: "FTP", code: -1)))
                    return
                }
                if bytesRead == 0 { break }

                var offset = 0
                while offset < bytesRead {
                    let bytesWritten = writeStream.write(
                        &buffer[offset],
                        maxLength: bytesRead - offset
                    )
                    if bytesWritten < 0 {
                        let error = writeStream.streamError
                        self.deliverFailure(
                            onFailure,
                            error: .uploadFailed(error?.localizedDescription ?? "写入流错误")
                        )
                        return
                    }
                    if bytesWritten == 0 { break }
                    offset += bytesWritten
                    uploadedBytes += bytesWritten
                }

                // 进度回调
                let progress = Double(uploadedBytes) / Double(totalBytes)
                DispatchQueue.main.async {
                    onProgress?(progress)
                }
            }

            // 检查写入流状态
            let status = writeStream.streamStatus
            if status == .atEnd || status == .closed {
                print("[FTPUploader] 上传完成")
                self.deliverSuccess(onSuccess)
            } else if let error = writeStream.streamError {
                self.deliverFailure(onFailure, error: .uploadFailed(error.localizedDescription))
            } else {
                self.deliverSuccess(onSuccess)
            }
        }
    }

    // MARK: - 上传 UIImage（便捷方法）

    /// 上传 UIImage 到 FTP 服务器
    func uploadImage(
        _ image: UIImage,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (FTPUploadError) -> Void
    ) {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            deliverFailure(onFailure, error: .fileReadFailed)
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "IMG_\(timestampString()).jpg"
        let tempURL = tempDir.appendingPathComponent(fileName)

        do {
            try imageData.write(to: tempURL)
            uploadFile(
                localURL: tempURL,
                onProgress: onProgress,
                onSuccess: {
                    try? FileManager.default.removeItem(at: tempURL)
                    onSuccess()
                },
                onFailure: { error in
                    try? FileManager.default.removeItem(at: tempURL)
                    onFailure(error)
                }
            )
        } catch {
            deliverFailure(onFailure, error: .fileReadFailed)
        }
    }

    /// 上传视频文件到 FTP 服务器
    func uploadVideo(
        _ videoURL: URL,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (FTPUploadError) -> Void
    ) {
        uploadFile(
            localURL: videoURL,
            onProgress: onProgress,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    // MARK: - 工具方法

    /// 构建远程路径
    private func buildRemotePath(fileName: String) -> String {
        var dir = FTPConfig.remoteDir
        if !dir.hasSuffix("/") { dir += "/" }
        if dir.hasPrefix("/") { dir = String(dir.dropFirst()) }
        return "ftp://\(FTPConfig.username):\(FTPConfig.password)@\(FTPConfig.host):\(FTPConfig.port)/\(dir)\(fileName)"
    }

    /// 主线程回调
    private func deliverSuccess(_ handler: @escaping () -> Void) {
        DispatchQueue.main.async { handler() }
    }

    private func deliverFailure(_ handler: @escaping (FTPUploadError) -> Void, error: FTPUploadError) {
        DispatchQueue.main.async { handler(error) }
    }

    /// 生成时间戳文件名
    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
