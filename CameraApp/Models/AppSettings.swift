//
//  AppSettings.swift
//  CameraApp
//
//  应用设置数据模型（持久化到UserDefaults）
//  路径: CameraApp/Models/AppSettings.swift
//

import Foundation
import SwiftUI

// MARK: - 坐标格式枚举

/// 坐标显示格式
enum CoordinateFormat: String, CaseIterable, Identifiable {
    /// 十进制度：116.407400°E
    case decimal = "十进制度"
    /// 度分秒：116°24'26.6"E
    case dms = "度分秒"

    var id: String { rawValue }
}

// MARK: - 相机模式

/// 相机工作模式
enum CameraMode: String, CaseIterable {
    case photo = "拍照"
    case video = "录像"
}

// MARK: - 上传目标

/// 文件上传目标
enum UploadTarget: String, CaseIterable, Identifiable {
    case ftp = "FTP"
    case baidu = "百度网盘"

    var id: String { rawValue }
}

// MARK: - 应用设置（持久化存储）

/// 全局设置模型，所有设置自动保存到UserDefaults
class AppSettings: ObservableObject {

    private let defaults = UserDefaults.standard

    // MARK: FTP上传

    @Published var autoUpload: Bool {
        didSet { defaults.set(autoUpload, forKey: "autoUpload") }
    }

    @Published var ftpHost: String {
        didSet { defaults.set(ftpHost, forKey: "ftpHost") }
    }

    @Published var ftpPort: String {
        didSet { defaults.set(ftpPort, forKey: "ftpPort") }
    }

    @Published var ftpUsername: String {
        didSet { defaults.set(ftpUsername, forKey: "ftpUsername") }
    }

    @Published var ftpPassword: String {
        didSet { defaults.set(ftpPassword, forKey: "ftpPassword") }
    }

    @Published var ftpRemoteDir: String {
        didSet { defaults.set(ftpRemoteDir, forKey: "ftpRemoteDir") }
    }

    // MARK: 上传目标

    @Published var uploadTarget: UploadTarget {
        didSet { defaults.set(uploadTarget.rawValue, forKey: "uploadTarget") }
    }

    // MARK: 坐标格式

    @Published var coordinateFormat: CoordinateFormat {
        didSet { defaults.set(coordinateFormat.rawValue, forKey: "coordinateFormat") }
    }

    // MARK: 水印设置

    @Published var watermarkFontSize: CGFloat {
        didSet { defaults.set(Double(watermarkFontSize), forKey: "watermarkFontSize") }
    }

    @Published var watermarkVerticalPosition: Double {
        didSet { defaults.set(watermarkVerticalPosition, forKey: "watermarkVerticalPosition") }
    }

    // MARK: - 初始化（从UserDefaults读取已保存的设置）

    init() {
        // FTP 设置
        self.autoUpload = defaults.bool(forKey: "autoUpload")
        self.ftpHost = defaults.string(forKey: "ftpHost") ?? ""
        self.ftpPort = defaults.string(forKey: "ftpPort") ?? "21"
        self.ftpUsername = defaults.string(forKey: "ftpUsername") ?? ""
        self.ftpPassword = defaults.string(forKey: "ftpPassword") ?? ""
        self.ftpRemoteDir = defaults.string(forKey: "ftpRemoteDir") ?? "/"

        // 上传目标
        if let targetRaw = defaults.string(forKey: "uploadTarget"),
           let target = UploadTarget(rawValue: targetRaw) {
            self.uploadTarget = target
        } else {
            self.uploadTarget = .ftp
        }

        // 坐标格式
        if let formatRaw = defaults.string(forKey: "coordinateFormat"),
           let format = CoordinateFormat(rawValue: formatRaw) {
            self.coordinateFormat = format
        } else {
            self.coordinateFormat = .decimal
        }

        // 水印设置
        let fontSize = defaults.double(forKey: "watermarkFontSize")
        self.watermarkFontSize = fontSize > 0 ? CGFloat(fontSize) : 24
        self.watermarkVerticalPosition = defaults.object(forKey: "watermarkVerticalPosition") as? Double ?? 0.15
    }
}
