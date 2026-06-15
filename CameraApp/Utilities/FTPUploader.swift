//
//  FTPUploader.swift
//  CameraApp
//
//  FTP 文件上传工具类
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
        }
    }
}

// MARK: - FTP 上传工具类

final class FTPUploader: NSObject {

    static let shared = FTPUploader()

    private var currentSession: URLSession?
    private var successHandler: (() -> Void)?
    private var failureHandler: ((FTPUploadError) -> Void)?
    private var progressHandler: ((Double) -> Void)?
    private var currentData = Data()

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

        // 直接拼接 FTP URL
        let ftpURLString = "ftp://\(FTPConfig.username):\(FTPConfig.password)@\(FTPConfig.host):\(FTPConfig.port)\(dir)\(fileName)"

        print("[FTPUploader] 目标: ftp://\(FTPConfig.username):***@\(FTPConfig.host):\(FTPConfig.port)\(dir)\(fileName)")
        print("[FTPUploader] 文件大小: \(fileData.count) bytes")

        guard let ftpURL = URL(string: ftpURLString) else {
            DispatchQueue.main.async { onFailure(.uploadFailed("无效的 FTP URL，请检查配置")) }
            return
        }

        // 保存回调
        self.successHandler = onSuccess
        self.failureHandler = onFailure
        self.progressHandler = onProgress

        // 创建 URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.currentSession = urlSession

        // 构建 PUT 请求
        var request = URLRequest(url: ftpURL)
        request.httpMethod = "PUT"

        // 使用 data task 上传数据
        let task = urlSession.uploadTask(with: request, from: fileData)
        task.resume()
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

    /// 测试 FTP 连接是否正常
    func testConnection(completion: @escaping (Result<String, String>) -> Void) {
        guard !FTPConfig.host.isEmpty else {
            completion(.failure("未配置 FTP 服务器信息"))
            return
        }

        let testContent = "FTP connection test - \(timestampString())"
        guard let testData = testContent.data(using: .utf8) else {
            completion(.failure("创建测试数据失败"))
            return
        }

        var dir = FTPConfig.remoteDir
        if !dir.hasPrefix("/") { dir = "/" + dir }
        if !dir.hasSuffix("/") { dir += "/" }

        let ftpURLString = "ftp://\(FTPConfig.username):\(FTPConfig.password)@\(FTPConfig.host):\(FTPConfig.port)\(dir)test_connection.txt"

        guard let ftpURL = URL(string: ftpURLString) else {
            completion(.failure("无效的 FTP URL"))
            return
        }

        self.successHandler = {
            completion(.success("FTP 连接正常"))
        }
        self.failureHandler = { error in
            completion(.failure(error.localizedDescription))
        }
        self.progressHandler = nil

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.currentSession = urlSession

        var request = URLRequest(url: ftpURL)
        request.httpMethod = "PUT"
        let task = urlSession.uploadTask(with: request, from: testData)
        task.resume()
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - URLSessionTaskDelegate

extension FTPUploader: URLSessionTaskDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        session.finishTasksAndInvalidate()

        if let error = error {
            let nsError = error as NSError
            print("[FTPUploader] 完成(错误): domain=\(nsError.domain), code=\(nsError.code), desc=\(nsError.localizedDescription)")

            // code 0 或 -999(cancelled) 可能实际是成功
            if nsError.code == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.successHandler?()
                }
            } else {
                let message = "错误码: \(nsError.code)\n\(nsError.localizedDescription)"
                DispatchQueue.main.async { [weak self] in
                    self?.failureHandler?(.uploadFailed(message))
                }
            }
        } else {
            print("[FTPUploader] 上传成功")
            DispatchQueue.main.async { [weak self] in
                self?.successHandler?()
            }
        }
    }
}
