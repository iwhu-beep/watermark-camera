//
//  CloudUploader.swift
//  CameraApp
//
//  基于Alamofire封装的阿里云盘文件上传工具类
//  路径: CameraApp/Utilities/CloudUploader.swift
//
//  功能：AccessToken自动刷新、分片上传、进度回调、网盘文件地址返回
//  依赖：Alamofire（需通过SPM添加：https://github.com/Alamofire/Alamofire）
//
//  阿里云盘开放平台文档：https://www.alipan.com/drive/open/platform
//

import Alamofire
import Foundation
import UIKit

// MARK: - 配置项

/// 阿里云盘开放平台配置（填入自己申请的凭据即可使用）
struct AliyunDriveConfig {

    /// 开放平台应用 Client ID（必填）
    /// 获取方式：https://open.alipan.com 创建应用 → 应用列表 → AppId
    static var clientId: String = ""

    /// 用户 Refresh Token（必填，用于自动刷新 Access Token）
    /// 获取方式：OAuth2授权流程 或 开放平台调试工具
    static var refreshToken: String = ""

    /// 上传目标文件夹ID（默认根目录 "root"）
    static var uploadFolderId: String = "root"

    /// 分片大小（字节），默认 4MB
    /// 阿里云盘要求每个分片 100KB~5GB，推荐 4MB
    static var partSize: Int = 4 * 1024 * 1024
}

// MARK: - 上传错误

/// 上传错误类型
enum UploadError: Error, LocalizedError {
    /// 未配置 ClientID 或 RefreshToken
    case notConfigured
    /// Access Token 刷新失败
    case tokenRefreshFailed(String)
    /// 未获取到 drive_id
    case driveIdNotFound
    /// 本地文件读取失败
    case fileReadFailed
    /// 创建文件记录失败
    case createFileFailed(String)
    /// 未获取到上传地址
    case uploadUrlNotFound
    /// 分片上传失败
    case partUploadFailed(partNumber: Int, message: String)
    /// 完成上传失败
    case completeFailed(String)
    /// 未获取到下载地址
    case downloadUrlNotFound
    /// 网络错误
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置阿里云盘 ClientID 或 RefreshToken"
        case .tokenRefreshFailed(let msg):
            return "Token刷新失败: \(msg)"
        case .driveIdNotFound:
            return "未获取到 drive_id"
        case .fileReadFailed:
            return "本地文件读取失败"
        case .createFileFailed(let msg):
            return "创建文件失败: \(msg)"
        case .uploadUrlNotFound:
            return "未获取到上传地址"
        case .partUploadFailed(let part, let msg):
            return "分片\(part)上传失败: \(msg)"
        case .completeFailed(let msg):
            return "完成上传失败: \(msg)"
        case .downloadUrlNotFound:
            return "未获取到文件下载地址"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - 回调类型

/// 上传进度回调（0.0 ~ 1.0）
typealias UploadProgressCallback = (_ fractionCompleted: Double) -> Void

/// 上传成功回调（返回网盘文件下载地址）
typealias UploadSuccessCallback = (_ downloadUrl: String) -> Void

/// 上传失败回调
typealias UploadFailureCallback = (_ error: UploadError) -> Void

// MARK: - API 响应模型

/// Token 刷新响应
private struct TokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case code
        case message
    }
}

/// 用户信息响应（获取 drive_id）
private struct UserInfoResponse: Decodable {
    let defaultDriveId: String?
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case defaultDriveId = "default_drive_id"
        case code
        case message
    }
}

/// 创建文件响应
private struct CreateFileResponse: Decodable {
    let driveId: String?
    let fileId: String?
    let uploadId: String?
    let partInfoList: [PartInfoItem]?
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case driveId = "drive_id"
        case fileId = "file_id"
        case uploadId = "upload_id"
        case partInfoList = "part_info_list"
        case code
        case message
    }
}

/// 分片信息
private struct PartInfoItem: Decodable {
    let partNumber: Int?
    let uploadUrl: String?

    enum CodingKeys: String, CodingKey {
        case partNumber = "part_number"
        case uploadUrl = "upload_url"
    }
}

/// 完成上传响应
private struct CompleteUploadResponse: Decodable {
    let fileId: String?
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case code
        case message
    }
}

/// 下载地址响应
private struct DownloadUrlResponse: Decodable {
    let url: String?
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case url
        case code
        case message
    }
}

// MARK: - 云盘上传工具类

/// 阿里云盘文件上传工具（单例）
///
/// 用法示例：
/// ```swift
/// // 1. 配置凭据（通常在 AppDelegate 或设置页）
/// AliyunDriveConfig.clientId = "your_client_id"
/// AliyunDriveConfig.refreshToken = "your_refresh_token"
/// AliyunDriveConfig.uploadFolderId = "root"
///
/// // 2. 上传本地图片
/// CloudUploader.shared.uploadFile(
///     localURL: imageURL,
///     onProgress: { progress in print("进度: \(progress)") },
///     onSuccess: { url in print("下载地址: \(url)") },
///     onFailure: { error in print("失败: \(error)") }
/// )
/// ```
final class CloudUploader {

    static let shared = CloudUploader()

    // MARK: - 私有属性

    /// API 基础 URL
    private let baseURL = "https://open.aliyundrive.com"

    /// 缓存的 Access Token
    private var cachedAccessToken: String?

    /// 缓存的 drive_id
    private var cachedDriveId: String?

    /// 上传用的安全队列
    private let serialQueue = DispatchQueue(label: "com.cameraapp.clouduploader")

    private init() {}

    // MARK: - 公开接口：本地文件URL上传

    /// 上传本地图片文件到阿里云盘
    ///
    /// 完整流程：刷新Token → 获取drive_id → 创建文件 → 分片上传 → 完成上传 → 获取下载地址
    ///
    /// - Parameters:
    ///   - localURL: 本地图片文件URL
    ///   - folderId: 目标文件夹ID（为空则使用 AliyunDriveConfig.uploadFolderId）
    ///   - onProgress: 上传进度回调（0.0~1.0），主线程
    ///   - onSuccess: 上传成功回调，返回网盘文件下载地址，主线程
    ///   - onFailure: 上传失败回调，主线程
    func uploadFile(
        localURL: URL,
        folderId: String? = nil,
        onProgress: UploadProgressCallback? = nil,
        onSuccess: @escaping UploadSuccessCallback,
        onFailure: @escaping UploadFailureCallback
    ) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            // 0. 配置校验
            guard !AliyunDriveConfig.clientId.isEmpty,
                  !AliyunDriveConfig.refreshToken.isEmpty else {
                self.deliverOnMain(onFailure, value: .notConfigured)
                return
            }

            // 1. 读取本地文件数据
            guard let fileData = try? Data(contentsOf: localURL) else {
                self.deliverOnMain(onFailure, value: .fileReadFailed)
                return
            }

            let fileName = localURL.lastPathComponent

            // 2. 确保 Token 有效
            self.ensureToken { result in
                switch result {
                case .success(let accessToken):

                    // 3. 确保 drive_id 已获取
                    self.ensureDriveId(accessToken: accessToken) { driveResult in
                        switch driveResult {
                        case .success(let driveId):

                            let targetFolderId = folderId ?? AliyunDriveConfig.uploadFolderId

                            // 4. 创建文件（获取上传地址）
                            self.createFile(
                                accessToken: accessToken,
                                driveId: driveId,
                                folderId: targetFolderId,
                                fileName: fileName,
                                fileSize: fileData.count
                            ) { createResult in
                                switch createResult {
                                case .success(let fileId, let uploadId, let partInfoList):

                                    // 5. 分片上传
                                    self.uploadParts(
                                        fileData: fileData,
                                        partInfoList: partInfoList,
                                        accessToken: accessToken,
                                        onProgress: onProgress
                                    ) { uploadResult in
                                        switch uploadResult {
                                        case .success:

                                            // 6. 完成上传
                                            self.completeUpload(
                                                accessToken: accessToken,
                                                driveId: driveId,
                                                fileId: fileId,
                                                uploadId: uploadId
                                            ) { completeResult in
                                                switch completeResult {
                                                case .success:

                                                    // 7. 获取下载地址
                                                    self.getDownloadUrl(
                                                        accessToken: accessToken,
                                                        driveId: driveId,
                                                        fileId: fileId
                                                    ) { urlResult in
                                                        switch urlResult {
                                                        case .success(let downloadUrl):
                                                            self.deliverOnMain(onSuccess, value: downloadUrl)
                                                        case .failure(let error):
                                                            self.deliverOnMain(onFailure, value: error)
                                                        }
                                                    }

                                                case .failure(let error):
                                                    self.deliverOnMain(onFailure, value: error)
                                                }
                                            }

                                        case .failure(let error):
                                            self.deliverOnMain(onFailure, value: error)
                                        }
                                    }

                                case .failure(let error):
                                    self.deliverOnMain(onFailure, value: error)
                                }
                            }

                        case .failure(let error):
                            self.deliverOnMain(onFailure, value: error)
                        }
                    }

                case .failure(let error):
                    self.deliverOnMain(onFailure, value: error)
                }
            }
        }
    }

    // MARK: - 公开接口：UIImage上传（便捷方法）

    /// 上传 UIImage 到阿里云盘（内部先写入临时文件再上传）
    func uploadImage(
        _ image: UIImage,
        folderId: String? = nil,
        onProgress: UploadProgressCallback? = nil,
        onSuccess: @escaping UploadSuccessCallback,
        onFailure: @escaping UploadFailureCallback
    ) {
        // 1. 转换为 JPEG 数据
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            deliverOnMain(onFailure, value: .fileReadFailed)
            return
        }

        // 2. 写入临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "IMG_\(timestampString()).jpg"
        let tempURL = tempDir.appendingPathComponent(fileName)

        do {
            try imageData.write(to: tempURL)

            // 3. 调用文件上传
            uploadFile(
                localURL: tempURL,
                folderId: folderId,
                onProgress: onProgress,
                onSuccess: { url in
                    // 上传成功后清理临时文件
                    try? FileManager.default.removeItem(at: tempURL)
                    onSuccess(url)
                },
                onFailure: { error in
                    try? FileManager.default.removeItem(at: tempURL)
                    onFailure(error)
                }
            )
        } catch {
            deliverOnMain(onFailure, value: .fileReadFailed)
        }
    }

    // MARK: - 手动刷新Token

    /// 手动刷新 Access Token
    func refreshAccessToken(completion: @escaping (Result<String, UploadError>) -> Void) {
        refreshTokenInternal(completion: completion)
    }

    // MARK: - Step 1: 确保 Token 有效

    private func ensureToken(completion: @escaping (Result<String, UploadError>) -> Void) {
        // 有缓存且未过期，直接使用
        if let token = cachedAccessToken, !token.isEmpty {
            completion(.success(token))
            return
        }

        // 刷新 Token
        refreshTokenInternal(completion: completion)
    }

    /// 刷新 Access Token
    ///
    /// POST /oauth/access_token
    /// { client_id, grant_type: "refresh_token", refresh_token }
    private func refreshTokenInternal(completion: @escaping (Result<String, UploadError>) -> Void) {
        let url = "\(baseURL)/oauth/access_token"
        let parameters: [String: String] = [
            "client_id": AliyunDriveConfig.clientId,
            "grant_type": "refresh_token",
            "refresh_token": AliyunDriveConfig.refreshToken
        ]

        AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: TokenResponse.self) { [weak self] response in
                switch response.result {
                case .success(let tokenResp):
                    // 检查API错误
                    if let message = tokenResp.message {
                        completion(.failure(.tokenRefreshFailed(message)))
                        return
                    }

                    guard let accessToken = tokenResp.accessToken else {
                        completion(.failure(.tokenRefreshFailed("响应中无 access_token")))
                        return
                    }

                    // 更新缓存
                    self?.cachedAccessToken = accessToken

                    // 更新 refresh_token（API会返回新的）
                    if let newRefreshToken = tokenResp.refreshToken {
                        AliyunDriveConfig.refreshToken = newRefreshToken
                    }

                    completion(.success(accessToken))

                case .failure(let error):
                    completion(.failure(.networkError(error)))
                }
            }
    }

    // MARK: - Step 2: 确保 drive_id 已获取

    /// 获取用户默认 drive_id
    ///
    /// POST /adrive/v1.0/userInfo
    private func ensureDriveId(
        accessToken: String,
        completion: @escaping (Result<String, UploadError>) -> Void
    ) {
        // 有缓存直接返回
        if let driveId = cachedDriveId, !driveId.isEmpty {
            completion(.success(driveId))
            return
        }

        let url = "\(baseURL)/adrive/v1.0/userInfo"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/json"
        ]

        AF.request(url, method: .post, headers: headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: UserInfoResponse.self) { [weak self] response in
                switch response.result {
                case .success(let userResp):
                    if let message = userResp.message {
                        completion(.failure(.driveIdNotFound))
                        return
                    }

                    guard let driveId = userResp.defaultDriveId else {
                        completion(.failure(.driveIdNotFound))
                        return
                    }

                    self?.cachedDriveId = driveId
                    completion(.success(driveId))

                case .failure:
                    completion(.failure(.driveIdNotFound))
                }
            }
    }

    // MARK: - Step 3: 创建文件

    /// 创建文件记录，获取上传地址
    ///
    /// POST /adrive/v1.0/openFile/create
    private func createFile(
        accessToken: String,
        driveId: String,
        folderId: String,
        fileName: String,
        fileSize: Int,
        completion: @escaping (Result<(fileId: String, uploadId: String, parts: [(partNumber: Int, uploadUrl: String)]), UploadError>) -> Void
    ) {
        let url = "\(baseURL)/adrive/v1.0/openFile/create"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/json;charset=UTF-8"
        ]

        // 计算分片数量
        let partSize = AliyunDriveConfig.partSize
        let partCount = max(1, (fileSize + partSize - 1) / partSize)

        // 构建分片信息列表
        var partInfoList: [[String: Int]] = []
        for i in 1...partCount {
            partInfoList.append(["part_number": i])
        }

        let parameters: [String: Any] = [
            "drive_id": driveId,
            "parent_file_id": folderId,
            "name": fileName,
            "type": "file",
            "check_name_mode": "auto_rename",
            "size": fileSize,
            "content_hash_name": "none",
            "part_info_list": partInfoList
        ]

        AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CreateFileResponse.self) { response in
                switch response.result {
                case .success(let createResp):
                    // 检查API错误
                    if let message = createResp.message {
                        completion(.failure(.createFileFailed(message)))
                        return
                    }

                    guard let fileId = createResp.fileId,
                          let uploadId = createResp.uploadId else {
                        completion(.failure(.createFileFailed("缺少 file_id 或 upload_id")))
                        return
                    }

                    // 提取分片上传地址
                    var parts: [(partNumber: Int, uploadUrl: String)] = []
                    if let partList = createResp.partInfoList {
                        for item in partList {
                            if let pn = item.partNumber, let uploadUrl = item.uploadUrl {
                                parts.append((partNumber: pn, uploadUrl: uploadUrl))
                            }
                        }
                    }

                    guard !parts.isEmpty else {
                        completion(.failure(.uploadUrlNotFound))
                        return
                    }

                    completion(.success((fileId: fileId, uploadId: uploadId, parts: parts)))

                case .failure(let error):
                    completion(.failure(.networkError(error)))
                }
            }
    }

    // MARK: - Step 4: 分片上传

    /// 逐片上传文件数据，支持进度回调
    private func uploadParts(
        fileData: Data,
        partInfoList: [(partNumber: Int, uploadUrl: String)],
        accessToken: String,
        onProgress: UploadProgressCallback?,
        completion: @escaping (Result<Void, UploadError>) -> Void
    ) {
        let totalSize = fileData.count
        let partSize = AliyunDriveConfig.partSize
        var uploadedBytes: Int64 = 0

        /// 递归上传下一片
        func uploadNextPart(index: Int) {
            guard index < partInfoList.count else {
                // 所有分片上传完毕
                onProgress?(1.0)
                completion(.success(()))
                return
            }

            let part = partInfoList[index]

            // 计算当前分片的数据范围（分片编号从1开始）
            let startOffset = (part.partNumber - 1) * partSize
            let endOffset = min(startOffset + partSize, totalSize)

            guard startOffset < totalSize else {
                uploadNextPart(index: index + 1)
                return
            }

            let partData = fileData[startOffset..<endOffset]
            let partByteCount = Int64(partData.count)

            let headers: HTTPHeaders = [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/octet-stream"
            ]

            AF.upload(partData, to: part.uploadUrl, method: .put, headers: headers)
                .uploadProgress { progress in
                    // 当前分片已上传字节 + 之前所有分片已上传字节
                    let currentPartUploaded = Int64(progress.fractionCompleted * Double(partByteCount))
                    let totalUploaded = uploadedBytes + currentPartUploaded
                    let fraction = Double(totalUploaded) / Double(totalSize)
                    DispatchQueue.main.async {
                        onProgress?(fraction)
                    }
                }
                .response { [weak self] response in
                    switch response.result {
                    case .success:
                        // 当前分片上传成功，累加已上传字节数
                        uploadedBytes += partByteCount

                        // 继续上传下一片
                        self?.serialQueue.async {
                            uploadNextPart(index: index + 1)
                        }

                    case .failure(let error):
                        completion(.failure(.partUploadFailed(
                            partNumber: part.partNumber,
                            message: error.localizedDescription
                        )))
                    }
                }
        }

        // 从第一片开始
        uploadNextPart(index: 0)
    }

    // MARK: - Step 5: 完成上传

    /// 通知服务器所有分片已上传完毕
    ///
    /// POST /adrive/v1.0/openFile/complete
    private func completeUpload(
        accessToken: String,
        driveId: String,
        fileId: String,
        uploadId: String,
        completion: @escaping (Result<Void, UploadError>) -> Void
    ) {
        let url = "\(baseURL)/adrive/v1.0/openFile/complete"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/json;charset=UTF-8"
        ]

        let parameters: [String: Any] = [
            "drive_id": driveId,
            "file_id": fileId,
            "upload_id": uploadId
        ]

        AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CompleteUploadResponse.self) { response in
                switch response.result {
                case .success(let completeResp):
                    if let message = completeResp.message {
                        completion(.failure(.completeFailed(message)))
                        return
                    }
                    completion(.success(()))

                case .failure(let error):
                    completion(.failure(.networkError(error)))
                }
            }
    }

    // MARK: - Step 6: 获取文件下载地址

    /// 获取已上传文件的下载URL
    ///
    /// POST /adrive/v1.0/openFile/getDownloadUrl
    private func getDownloadUrl(
        accessToken: String,
        driveId: String,
        fileId: String,
        completion: @escaping (Result<String, UploadError>) -> Void
    ) {
        let url = "\(baseURL)/adrive/v1.0/openFile/getDownloadUrl"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/json;charset=UTF-8"
        ]

        let parameters: [String: Any] = [
            "drive_id": driveId,
            "file_id": fileId
        ]

        AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: DownloadUrlResponse.self) { response in
                switch response.result {
                case .success(let downloadResp):
                    if let message = downloadResp.message {
                        completion(.failure(.downloadUrlNotFound))
                        return
                    }

                    guard let downloadUrl = downloadResp.url else {
                        completion(.failure(.downloadUrlNotFound))
                        return
                    }

                    completion(.success(downloadUrl))

                case .failure:
                    completion(.failure(.downloadUrlNotFound))
                }
            }
    }

    // MARK: - 工具方法

    /// 主线程回调
    private func deliverOnMain<T>(_ handler: @escaping (T) -> Void, value: T) {
        DispatchQueue.main.async {
            handler(value)
        }
    }

    /// 生成时间戳文件名
    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}