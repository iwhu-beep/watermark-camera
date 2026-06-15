//
//  FTPUploader.swift
//  CameraApp
//
//  FTP 文件上传工具类，使用 CFWriteStream
//  路径: CameraApp/Utilities/FTPUploader.swift
//

import Foundation
import UIKit

// MARK: - FTP 配置

/// FTP 服务器配置
struct FTPConfig {
    static var host: String = ""
    static var port: Int = 21
    static var username: String = ""
    static var password: String = ""
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
final class FTPUploader {

    static let shared = FTPUploader()
    private init() {}

    // MARK: - 上传本地文件

    func uploadFile(
        localURL: URL,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (FTPUploadError) -> Void
    ) {
        guard !FTPConfig.host.isEmpty else {
            deliverFailure(onFailure, error: .notConfigured)
            return
        }

        guard let fileData = try? Data(contentsOf: localURL) else {
            deliverFailure(onFailure, error: .fileReadFailed)
            return
        }

        let fileName = localURL.lastPathComponent
        let remotePath = buildRemotePath(fileName: fileName)

        guard let ftpURL = URL(string: remotePath) else {
            deliverFailure(onFailure, error: .connectionFailed("无效的 FTP URL"))
            return
        }

        print("[FTPUploader] 上传到: \(remotePath)")

        // 使用 InputStream 读取文件
        let inputStream = InputStream(data: fileData)
        inputStream.open()

        // 创建 CFWriteStream（返回 Unmanaged，需要 takeRetainedValue）
        let unmanaged = CFWriteStreamCreateWithFTPURL(
            kCFAllocatorDefault,
            ftpURL as CFURL
        )
        let writeStream = unmanaged.takeRetainedValue()

        // 设置用户名和密码
        CFWriteStreamSetProperty(
            writeStream,
            kCFStreamPropertyFTPUserName,
            FTPConfig.username as CFString
        )
        CFWriteStreamSetProperty(
            writeStream,
            kCFStreamPropertyFTPPassword,
            FTPConfig.password as CFString
        )
        // 被动模式
        CFWriteStreamSetProperty(
            writeStream,
            kCFStreamPropertyFTPUsePassiveMode,
            kCFBooleanTrue
        )

        let totalBytes = fileData.count
        var uploadedBytes = 0
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        writeStream.open()

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
                        buffer.advanced(by: offset),
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

                let progress = Double(uploadedBytes) / Double(max(totalBytes, 1))
                DispatchQueue.main.async { onProgress?(progress) }
            }

            let status = writeStream.streamStatus
            if status == .atEnd || status == .closed || status == .notOpen {
                if let error = writeStream.streamError {
                    self.deliverFailure(onFailure, error: .uploadFailed(error.localizedDescription))
                } else {
                    print("[FTPUploader] 上传完成")
                    self.deliverSuccess(onSuccess)
                }
            } else {
                self.deliverSuccess(onSuccess)
            }
        }
    }

    // MARK: - 上传 UIImage

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

    // MARK: - 上传视频

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

    private func buildRemotePath(fileName: String) -> String {
        var dir = FTPConfig.remoteDir
        if !dir.hasSuffix("/") { dir += "/" }
        return "ftp://\(FTPConfig.host):\(FTPConfig.port)\(dir)\(fileName)"
    }

    private func deliverSuccess(_ handler: @escaping () -> Void) {
        DispatchQueue.main.async { handler() }
    }

    private func deliverFailure(_ handler: @escaping (FTPUploadError) -> Void, error: FTPUploadError) {
        DispatchQueue.main.async { handler(error) }
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
