//
//  AppSettings.swift
//  CameraApp
//
//  应用设置数据模型
//  路径: CameraApp/Models/AppSettings.swift
//

import Foundation

// MARK: - 坐标格式枚举

/// 坐标显示格式
enum CoordinateFormat: String, CaseIterable, Identifiable {
    /// 十进制度：116.407400°E
    case decimal = "十进制度"
    /// 度分秒：116°24'26.6"E
    case dms = "度分秒"

    var id: String { rawValue }
}

// MARK: - 应用设置

/// 全局设置模型，ObservableObject驱动UI刷新
class AppSettings: ObservableObject {

    // MARK: 云盘上传

    /// 是否开启自动上传到阿里云盘
    @Published var autoUpload: Bool = false

    /// 阿里云盘开放平台 Client ID
    @Published var aliyunClientId: String = ""

    /// 阿里云盘 Refresh Token（用于自动刷新 Access Token）
    @Published var aliyunRefreshToken: String = ""

    /// 上传目标文件夹ID（默认根目录 "root"）
    @Published var uploadFolderId: String = "root"

    // MARK: 坐标格式

    /// 坐标显示格式
    @Published var coordinateFormat: CoordinateFormat = .decimal

    // MARK: 水印设置

    /// 水印基准字体大小（实际绘制时会按图片宽度缩放）
    @Published var watermarkFontSize: CGFloat = 20
}
