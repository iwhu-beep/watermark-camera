//
//  BaiduUploader.swift
//  CameraApp
//
//  百度网盘上传工具类
//  路径: CameraApp/Utilities/BaiduUploader.swift
//

import Foundation
import UIKit
import CommonCrypto

// MARK: - 百度网盘配置

struct BaiduConfig {
    static let appKey = "TlhzZGIrbZkFfDUWjEHi7PQHCDH0mu50"
    static let secretKey = "npJQQXl3D5MYKtHiNbCjZIIfG862h7l5"
    static let redirectURI = "oob"
    static let authURL = "https://openapi.baidu.com/oauth/2.0/authorize"
    static let tokenURL = "https://openapi.baidu.com/oauth/2.0/token"
    static let uploadURL = "https://d.pcs.baidu.com/rest/2.0/pcs/file"
    static let precreateURL = "https://pan.baidu.com/rest/2.0/xpan/file"
}

// MARK: - 上传错误

enum BaiduUploadError: Error, LocalizedError {
    case notAuthorized
    case fileReadFailed
    case uploadFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "未登录百度网盘"
        case .fileReadFailed: return "读取本地文件失败"
        case .uploadFailed(let msg): return "上传失败: \(msg)"
        case .networkError(let error): return "网络错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - 百度网盘上传工具类

final class BaiduUploader: NSObject {

    static let shared = BaiduUploader()

    private override init() { super.init() }

    // MARK: - 授权URL

    /// 获取 OAuth 授权页面 URL
    func authorizationURL() -> URL {
        var components = URLComponents(string: BaiduConfig.authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: BaiduConfig.appKey),
            URLQueryItem(name: "redirect_uri", value: BaiduConfig.redirectURI),
            URLQueryItem(name: "scope", value: "basic,netdisk"),
            URLQueryItem(name: "display", value: "mobile")
        ]
        return components.url!
    }

    // MARK: - 获取 Access Token

    /// 用授权码换取 Access Token
    func exchangeCodeForToken(
        code: String,
        completion: @escaping (Bool, String) -> Void
    ) {
        var components = URLComponents(string: BaiduConfig.tokenURL)!
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: BaiduConfig.appKey),
            URLQueryItem(name: "client_secret", value: BaiduConfig.secretKey),
            URLQueryItem(name: "redirect_uri", value: BaiduConfig.redirectURI)
        ]

        guard let url = components.url else {
            completion(false, "无效的 Token URL")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(false, "解析响应失败")
                    return
                }

                if let accessToken = json["access_token"] as? String,
                   let refreshToken = json["refresh_token"] as? String {
                    // 保存 token
                    UserDefaults.standard.set(accessToken, forKey: "baiduAccessToken")
                    UserDefaults.standard.set(refreshToken, forKey: "baiduRefreshToken")
                    UserDefaults.standard.set(Date().timeIntervalSince1970 + 2592000, forKey: "baiduTokenExpireTime")
                    print("[BaiduUploader] 授权成功，access_token: \(accessToken.prefix(10))...")
                    completion(true, "授权成功")
                } else if let errorDesc = json["error_description"] as? String {
                    completion(false, errorDesc)
                } else {
                    completion(false, "获取 token 失败")
                }
            }
        }
        task.resume()
    }

    // MARK: - 上传文件

    /// 上传本地文件到百度网盘
    func uploadFile(
        localURL: URL,
        remotePath: String,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (BaiduUploadError) -> Void
    ) {
        guard let accessToken = UserDefaults.standard.string(forKey: "baiduAccessToken"),
              !accessToken.isEmpty else {
            DispatchQueue.main.async { onFailure(.notAuthorized) }
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

        print("[BaiduUploader] 上传到: \(remotePath), 大小: \(fileData.count) bytes")

        // 步骤1: 预上传
        precreateFile(
            accessToken: accessToken,
            remotePath: remotePath,
            fileSize: fileData.count,
            fileData: fileData,
            onProgress: onProgress,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    // MARK: - 预上传

    private func precreateFile(
        accessToken: String,
        remotePath: String,
        fileSize: Int,
        fileData: Data,
        onProgress: ((Double) -> Void)?,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (BaiduUploadError) -> Void
    ) {
        // 计算 MD5
        let contentMD5 = md5(data: fileData)
        let blockMD5 = contentMD5

        var components = URLComponents(string: BaiduConfig.precreateURL)!
        components.path = "/rest/2.0/xpan/file"
        components.queryItems = [
            URLQueryItem(name: "method", value: "precreate"),
            URLQueryItem(name: "access_token", value: accessToken)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "path": remotePath,
            "size": "\(fileSize)",
            "isdir": "0",
            "autoinit": "1",
            "block_list": "[\"\(blockMD5)\"]",
            "content-md5": contentMD5,
            "rtype": "2"
        ]

        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&").data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { onFailure(.networkError(error)) }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { onFailure(.uploadFailed("预上传响应解析失败")) }
                return
            }

            let errno = json["errno"] as? Int ?? -1
            guard errno == 0, let uploadid = json["uploadid"] as? String else {
                let msg = "预上传失败 (errno=\(errno))"
                DispatchQueue.main.async { onFailure(.uploadFailed(msg)) }
                return
            }

            print("[BaiduUploader] 预上传成功, uploadid: \(uploadid.prefix(10))...")

            // 步骤2: 上传分片
            self?.uploadBlock(
                accessToken: accessToken,
                remotePath: remotePath,
                uploadid: uploadid,
                fileData: fileData,
                onProgress: onProgress,
                onSuccess: { [weak self] in
                    // 步骤3: 合并文件
                    self?.createFile(
                        accessToken: accessToken,
                        remotePath: remotePath,
                        uploadid: uploadid,
                        blockMD5: blockMD5,
                        fileSize: fileSize,
                        onSuccess: onSuccess,
                        onFailure: onFailure
                    )
                },
                onFailure: onFailure
            )
        }
        task.resume()
    }

    // MARK: - 上传分片

    private func uploadBlock(
        accessToken: String,
        remotePath: String,
        uploadid: String,
        fileData: Data,
        onProgress: ((Double) -> Void)?,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (BaiduUploadError) -> Void
    ) {
        var components = URLComponents(string: "https://d.pcs.baidu.com/rest/2.0/pcs/superfile2")!
        components.queryItems = [
            URLQueryItem(name: "method", value: "upload"),
            URLQueryItem(name: "type", value: "tmpfile"),
            URLQueryItem(name: "access_token", value: accessToken),
            URLQueryItem(name: "path", value: remotePath),
            URLQueryItem(name: "uploadid", value: uploadid),
            URLQueryItem(name: "partseq", value: "0")
        ]

        guard let url = components.url else {
            DispatchQueue.main.async { onFailure(.uploadFailed("无效的上传 URL")) }
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // 使用 delegate 获取进度
        let delegate = UploadProgressDelegate(totalBytes: fileData.count, progressHandler: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { onFailure(.networkError(error)) }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let md5 = json["md5"] as? String else {
                DispatchQueue.main.async { onFailure(.uploadFailed("分片上传响应解析失败")) }
                return
            }

            print("[BaiduUploader] 分片上传成功, md5: \(md5.prefix(10))...")
            DispatchQueue.main.async { onSuccess() }
        }
        task.resume()
    }

    // MARK: - 合并文件

    private func createFile(
        accessToken: String,
        remotePath: String,
        uploadid: String,
        blockMD5: String,
        fileSize: Int,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (BaiduUploadError) -> Void
    ) {
        var components = URLComponents(string: BaiduConfig.precreateURL)!
        components.path = "/rest/2.0/xpan/file"
        components.queryItems = [
            URLQueryItem(name: "method", value: "create"),
            URLQueryItem(name: "access_token", value: accessToken)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "path": remotePath,
            "size": "\(fileSize)",
            "isdir": "0",
            "uploadid": uploadid,
            "block_list": "[\"\(blockMD5)\"]",
            "rtype": "2"
        ]

        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&").data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { onFailure(.networkError(error)) }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { onFailure(.uploadFailed("合并文件响应解析失败")) }
                return
            }

            let errno = json["errno"] as? Int ?? -1
            if errno == 0 {
                print("[BaiduUploader] 文件上传完成: \(remotePath)")
                DispatchQueue.main.async { onSuccess() }
            } else {
                let msg = "合并文件失败 (errno=\(errno))"
                DispatchQueue.main.async { onFailure(.uploadFailed(msg)) }
            }
        }
        task.resume()
    }

    // MARK: - MD5 计算

    private func md5(data: Data) -> String {
        // 使用 CC_MD5（需要导入 CommonCrypto）
        let length = Int(CC_MD5_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: length)
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 上传 UIImage

    func uploadImage(
        _ image: UIImage,
        fileNamePrefix: String? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (BaiduUploadError) -> Void
    ) {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            DispatchQueue.main.async { onFailure(.fileReadFailed) }
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())

        let fileName: String
        if let prefix = fileNamePrefix, !prefix.isEmpty {
            fileName = "\(prefix)_\(timestamp).jpg"
        } else {
            fileName = "IMG_\(timestamp).jpg"
        }
        let tempURL = tempDir.appendingPathComponent(fileName)

        do {
            try imageData.write(to: tempURL)
            let remotePath = "/apps/拍照/\(fileName)"
            uploadFile(
                localURL: tempURL,
                remotePath: remotePath,
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
        fileNamePrefix: String? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (BaiduUploadError) -> Void
    ) {
        let originalName = videoURL.lastPathComponent
        let fileName: String
        if let prefix = fileNamePrefix, !prefix.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            fileName = "\(prefix)_\(timestamp).mp4"
        } else {
            fileName = originalName
        }

        // 如果需要重命名，复制到新文件
        let uploadURL: URL
        if fileName != originalName {
            let tempDir = FileManager.default.temporaryDirectory
            uploadURL = tempDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: uploadURL)
            do {
                try FileManager.default.copyItem(at: videoURL, to: uploadURL)
            } catch {
                DispatchQueue.main.async { onFailure(.fileReadFailed) }
                return
            }
        } else {
            uploadURL = videoURL
        }

        let remotePath = "/apps/拍照/\(fileName)"
        uploadFile(
            localURL: uploadURL,
            remotePath: remotePath,
            onProgress: onProgress,
            onSuccess: {
                if uploadURL != videoURL {
                    try? FileManager.default.removeItem(at: uploadURL)
                }
                onSuccess()
            },
            onFailure: { error in
                if uploadURL != videoURL {
                    try? FileManager.default.removeItem(at: uploadURL)
                }
                onFailure(error)
            }
        )
    }

    // MARK: - 检查登录状态

    func isLoggedIn() -> Bool {
        guard let token = UserDefaults.standard.string(forKey: "baiduAccessToken"),
              !token.isEmpty else { return false }
        let expireTime = UserDefaults.standard.double(forKey: "baiduTokenExpireTime")
        return Date().timeIntervalSince1970 < expireTime
    }

    // MARK: - 退出登录

    func logout() {
        UserDefaults.standard.removeObject(forKey: "baiduAccessToken")
        UserDefaults.standard.removeObject(forKey: "baiduRefreshToken")
        UserDefaults.standard.removeObject(forKey: "baiduTokenExpireTime")
    }
}

// MARK: - 上传进度代理

private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let totalBytes: Int
    let progressHandler: ((Double) -> Void)?

    init(totalBytes: Int, progressHandler: ((Double) -> Void)?) {
        self.totalBytes = totalBytes
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.progressHandler?(progress)
        }
    }
}
