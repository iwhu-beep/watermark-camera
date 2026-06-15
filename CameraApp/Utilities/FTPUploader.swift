//
//  FTPUploader.swift
//  CameraApp
//
//  FTP 文件上传工具类，使用 CFWriteStream (Core Foundation FTP API)
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

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // 使用 InputStream 读取文件数据
            guard let inputStream = InputStream(url: localURL) else {
                self.deliverFailure(onFailure, error: .fileReadFailed)
                return
            }
            inputStream.open()

            // 创建 CFWriteStream
            let writeStreamUnmanaged = CFWriteStreamCreateWithFTPURL(
                kCFAllocatorDefault,
                ftpURL as CFURL
            )
            let writeStream: CFWriteStream = writeStreamUnmanaged.takeRetainedValue()

            // 设置 FTP 属性（使用 Unmanaged bridging）
            let username = FTPConfig.username as CFString
            let password = FTPConfig.password as CFString
            let passiveMode = kCFBooleanTrue

            CFWriteStreamSetProperty(
                writeStream,
                CFStreamPropertyKey(kCFStreamPropertyFTPUserName),
                username
            )
            CFWriteStreamSetProperty(
                writeStream,
                CFStreamPropertyKey(kCFStreamPropertyFTPPassword),
                password
            )
            CFWriteStreamSetProperty(
                writeStream,
                CFStreamPropertyKey(kCFStreamPropertyFTPUsePassiveMode),
                passiveMode
            )

            let totalBytes = fileData.count
            var uploadedBytes = 0
            let bufferSize = 65536
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            // 打开写入流
            let openResult = CFWriteStreamOpen(writeStream)
            guard openResult else {
                inputStream.close()
                self.deliverFailure(onFailure, error: .connectionFailed("无法打开 FTP 连接"))
                return
            }

            defer {
                CFWriteStreamClose(writeStream)
                inputStream.close()
            }

            // 逐块上传
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
                if bytesRead < 0 {
                    let error = inputStream.streamError
                    self.deliverFailure(
                        onFailure,
                        error: .networkError(error ?? NSError(domain: "FTP", code: -1))
                    )
                    return
                }
                if bytesRead == 0 { break }

                var remaining = bytesRead
                var offset = 0
                while remaining > 0 {
                    let written = CFWriteStreamWrite(
                        writeStream,
                        buffer.withUnsafeBufferPointer({ $0.baseAddress! + offset }),
                        remaining
                    )
                    if written < 0 {
                        let error = CFWriteStreamCopyError(writeStream)
                        let desc = error?.localizedDescription ?? "写入失败"
                        self.deliverFailure(onFailure, error: .uploadFailed(desc))
                        return
                    }
                    if written == 0 {
                        // 流满，等待
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    }
                    offset += written
                    remaining -= written
                    uploadedBytes += written
                }

                let progress = Double(uploadedBytes) / Double(max(totalBytes, 1))
                DispatchQueue.main.async { onProgress?(progress) }
            }

            print("[FTPUploader] 上传完成 (\(uploadedBytes) bytes)")
            self.deliverSuccess(onSuccess)
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
