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

// MARK: - 相机模式

/// 相机工作模式
enum CameraMode: String, CaseIterable {
    case photo = "拍照"
    case video = "录像"
}

// MARK: - 应用设置

/// 全局设置模型，ObservableObject驱动UI刷新
class AppSettings: ObservableObject {

    // MARK: FTP上传

    /// 是否开启自动上传
    @Published var autoUpload: Bool = false

    /// FTP 服务器地址（如 ftp.example.com）
    @Published var ftpHost: String = ""

    /// FTP 端口（默认21）
    @Published var ftpPort: String = "21"

    /// FTP 用户名
    @Published var ftpUsername: String = ""

    /// FTP 密码
    @Published var ftpPassword: String = ""

    /// FTP 远程目录（如 /photos/camera/）
    @Published var ftpRemoteDir: String = "/"

    // MARK: 坐标格式

    /// 坐标显示格式
    @Published var coordinateFormat: CoordinateFormat = .decimal

    // MARK: 水印设置

    /// 水印基准字体大小（实际绘制时会按图片宽度缩放）
    @Published var watermarkFontSize: CGFloat = 24

    /// 水印垂直位置（0=底部, 0.5=居中, 1=顶部）
    @Published var watermarkVerticalPosition: Double = 0.15
}
