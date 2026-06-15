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
    case uploadFailed(String)
    case networkError(Error)
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置 FTP 服务器信息"
        case .fileReadFailed:
            return "读取本地文件失败"
        case .uploadFailed(let msg):
            return "FTP 上传失败: \(msg)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .streamError(let msg):
            return msg
        }
    }
}

// MARK: - FTP 上传工具类

final class FTPUploader: NSObject {

    static let shared = FTPUploader()

    private var writeStream: OutputStream?
    private var dataToUpload: Data?
    private var bytesWritten: Int = 0
    private var streamRunLoop: RunLoop?
    private var streamThread: Thread?

    private var successHandler: (() -> Void)?
    private var failureHandler: ((FTPUploadError) -> Void)?
    private var progressHandler: ((Double) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - 上传本地文件

    func uploadFile(
        localURL: URL,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (FTPUploadError) -> Void
    ) {
        guard !FTPConfig.host.isEmpty else {
            DispatchQueue.main.async { onFailure(.notConfigured) }
            return
        }

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            DispatchQueue.main.async { onFailure(.fileReadFailed) }
            return
        }

        guard let fileData = try? Data(contentsOf: localURL) else {
            DispatchQueue.main.async { onFailure(.fileReadFailed) }
            return
        }

        let fileName = localURL.lastPathComponent
        var dir = FTPConfig.remoteDir
        if !dir.hasPrefix("/") { dir = "/" + dir }
        if !dir.hasSuffix("/") { dir += "/" }

        print("[FTPUploader] 目标: ftp://\(FTPConfig.username):***@\(FTPConfig.host):\(FTPConfig.port)\(dir)\(fileName)")
        print("[FTPUploader] 文件大小: \(fileData.count) bytes")

        self.successHandler = onSuccess
        self.failureHandler = onFailure
        self.progressHandler = onProgress

        // 使用 CFWriteStream 上传
        startStreamUpload(
            data: fileData,
            host: FTPConfig.host,
            port: FTPConfig.port,
            username: FTPConfig.username,
            password: FTPConfig.password,
            remotePath: "\(dir)\(fileName)"
        )
    }

    // MARK: - 上传 UIImage

    func uploadImage(
        _ image: UIImage,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (FTPUploadError) -> Void
    ) {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            DispatchQueue.main.async { onFailure(.fileReadFailed) }
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
            DispatchQueue.main.async { onFailure(.fileReadFailed) }
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

    // MARK: - 测试连接

    func testConnection(completion: @escaping (Bool, String) -> Void) {
        guard !FTPConfig.host.isEmpty else {
            completion(false, "未配置 FTP 服务器信息")
            return
        }

        let testContent = "FTP connection test - \(timestampString())"
        guard let testData = testContent.data(using: .utf8) else {
            completion(false, "创建测试数据失败")
            return
        }

        var dir = FTPConfig.remoteDir
        if !dir.hasPrefix("/") { dir = "/" + dir }
        if !dir.hasSuffix("/") { dir += "/" }

        self.successHandler = {
            completion(true, "FTP 连接正常")
        }
        self.failureHandler = { error in
            completion(false, error.localizedDescription)
        }
        self.progressHandler = nil

        startStreamUpload(
            data: testData,
            host: FTPConfig.host,
            port: FTPConfig.port,
            username: FTPConfig.username,
            password: FTPConfig.password,
            remotePath: "\(dir)test_connection.txt"
        )
    }

    // MARK: - CFWriteStream 上传实现

    private func startStreamUpload(
        data: Data,
        host: String,
        port: Int,
        username: String,
        password: String,
        remotePath: String
    ) {
        self.dataToUpload = data
        self.bytesWritten = 0

        // 创建 CFWriteStream
        guard let stream = CFWriteStreamCreateWithFTPURL(
            kCFAllocatorDefault,
            URL(string: "ftp://\(host):\(port)\(remotePath)")! as CFURL
        )?.takeRetainedValue() as OutputStream? else {
            DispatchQueue.main.async {
                self.failureHandler?(.streamError("创建 FTP 流失败"))
            }
            return
        }

        // 设置 FTP 凭据
        stream.setProperty(username as NSString, forKey: .init(kCFStreamPropertyFTPUserName))
        stream.setProperty(password as NSString, forKey: .init(kCFStreamPropertyFTPPassword))

        // 设置代理
        stream.delegate = self
        stream.schedule(in: .current, forMode: .common)

        // 打开流
        stream.open()
        self.writeStream = stream

        print("[FTPUploader] 流已打开，等待连接...")
    }

    // MARK: - 工具方法

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private func cleanup() {
        writeStream?.close()
        writeStream?.remove(from: .current, forMode: .common)
        writeStream = nil
        dataToUpload = nil
    }
}

// MARK: - StreamDelegate

extension FTPUploader: StreamDelegate {

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        print("[FTPUploader] 流事件: \(eventCode.rawValue)")

        switch eventCode {
        case .openCompleted:
            if let error = aStream.streamError {
                print("[FTPUploader] 打开失败: \(error.localizedDescription)")
                cleanup()
                DispatchQueue.main.async {
                    self.failureHandler?(.streamError("连接失败: \(error.localizedDescription)"))
                }
            } else {
                print("[FTPUploader] 连接成功，开始写入数据")
                writeToStream()
            }

        case .hasSpaceAvailable:
            writeToStream()

        case .endEncountered:
            print("[FTPUploader] 写入完成")
            cleanup()
            DispatchQueue.main.async {
                self.successHandler?()
            }

        case .errorOccurred:
            if let error = aStream.streamError {
                print("[FTPUploader] 流错误: \(error.localizedDescription)")
                cleanup()
                DispatchQueue.main.async {
                    self.failureHandler?(.streamError("上传错误: \(error.localizedDescription)"))
                }
            }

        default:
            break
        }
    }

    private func writeToStream() {
        guard let stream = writeStream,
              let data = dataToUpload,
              stream.hasSpaceAvailable else { return }

        let totalBytes = data.count

        // 写入数据块
        let chunkSize = 4096
        while bytesWritten < totalBytes && stream.hasSpaceAvailable {
            let remainingBytes = totalBytes - bytesWritten
            let bytesToWrite = min(chunkSize, remainingBytes)

            let bytesWrittenThisChunk = data.withUnsafeBytes { bufferPointer -> Int in
                guard let baseAddress = bufferPointer.baseAddress else { return -1 }
                let ptr = baseAddress.advanced(by: bytesWritten)
                return stream.write(ptr.assumingMemoryBound(to: UInt8.self), maxLength: bytesToWrite)
            }

            if bytesWrittenThisChunk < 0 {
                if let error = stream.streamError {
                    print("[FTPUploader] 写入错误: \(error.localizedDescription)")
                    cleanup()
                    DispatchQueue.main.async {
                        self.failureHandler?(.streamError("写入失败: \(error.localizedDescription)"))
                    }
                }
                return
            }

            bytesWritten += bytesWrittenThisChunk

            // 报告进度
            let progress = Double(bytesWritten) / Double(totalBytes)
            DispatchQueue.main.async {
                self.progressHandler?(progress)
            }
        }

        // 所有数据写入完成
        if bytesWritten >= totalBytes {
            print("[FTPUploader] 数据写入完成 (\(bytesWritten) bytes)")
            cleanup()
            DispatchQueue.main.async {
                self.successHandler?()
            }
        }
    }
}
