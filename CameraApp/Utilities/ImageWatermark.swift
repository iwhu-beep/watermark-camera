//
//  ImageWatermark.swift
//  CameraApp
//
//  独立水印绘制工具类：输入UIImage+经纬度+备注，输出左下角水印新图
//  路径: CameraApp/Utilities/ImageWatermark.swift
//

import UIKit

/// 独立图片水印工具类，无外部依赖，可直接调用
///
/// 用法示例：
/// ```swift
/// let result = ImageWatermark.draw(
///     on: originalImage,
///     coordinate: "经度：116.407400°E 纬度：39.904200°N",
///     note: "施工现场"
/// )
/// ```
struct ImageWatermark {

    // MARK: - 常量

    /// 基准设计宽度（以1000px为参考，所有尺寸按此缩放）
    private static let referenceWidth: CGFloat = 1000

    /// 基准字体大小（在1000px宽图片上的字号）
    private static let baseFontSize: CGFloat = 24

    /// 基准边距（在1000px宽图片上距边缘20pt）
    private static let baseMargin: CGFloat = 20

    /// 基准描边宽度（在1000px宽图片上1pt黑色描边）
    private static let baseStrokeWidth: CGFloat = 1

    /// 行间距倍数（相对字体大小）
    private static let lineSpacingRatio: CGFloat = 0.35

    // MARK: - 公开接口

    /// 在图片左下角绘制水印，返回新UIImage（不修改原图）
    ///
    /// 水印从下到上排列：
    /// - 第一行（最底）：经纬度坐标
    /// - 第二行（中间）：拍照时刻日期时间
    /// - 第三行（最顶）：备注（为空则不绘制）
    ///
    /// 样式：白色填充 + 黑色描边，强光下清晰可见
    /// 布局：距左边缘和底边缘各20pt，字号/描边按图片尺寸等比缩放
    ///
    /// - Parameters:
    ///   - image: 原始照片
    ///   - coordinate: 经纬度文本，如 "经度：116.407400°E 纬度：39.904200°N"
    ///   - note: 备注文本，为空则只绘制两行（日期+坐标）
    /// - Returns: 添加水印后的新UIImage
    static func draw(
        on image: UIImage,
        coordinate: String,
        note: String? = nil
    ) -> UIImage {

        let imgWidth = image.size.width
        let imgHeight = image.size.height

        // 按图片宽度相对参考宽度计算缩放因子
        let scale = imgWidth / referenceWidth

        // 缩放后实际尺寸
        let fontSize = baseFontSize * scale
        let margin = baseMargin * scale
        let strokeWidth = baseStrokeWidth * scale
        let lineSpacing = fontSize * lineSpacingRatio

        // 文字属性：白色填充 + 黑色描边
        // strokeWidth 为负值 → 同时执行 fill + stroke
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -strokeWidth
        ]

        // 生成日期时间文本
        let dateTimeText = formatDateTime()

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in

            // 绘制原始照片
            image.draw(at: .zero)

            // 从底部向上依次绘制水印行
            // 底行：坐标 → 日期时间 → 备注
            var currentY = imgHeight - margin

            // 第一行（最底）：经纬度坐标
            let line1Size = coordinate.size(withAttributes: textAttributes)
            currentY -= line1Size.height
            coordinate.draw(
                at: CGPoint(x: margin, y: currentY),
                withAttributes: textAttributes
            )

            // 第二行（中间）：日期时间
            let line2Size = dateTimeText.size(withAttributes: textAttributes)
            currentY -= line2Size.height + lineSpacing
            dateTimeText.draw(
                at: CGPoint(x: margin, y: currentY),
                withAttributes: textAttributes
            )

            // 第三行（最顶）：备注（为空则跳过）
            if let note = note, !note.isEmpty {
                let line3Size = note.size(withAttributes: textAttributes)
                currentY -= line3Size.height + lineSpacing
                note.draw(
                    at: CGPoint(x: margin, y: currentY),
                    withAttributes: textAttributes
                )
            }
        }
    }

    // MARK: - 私有工具

    /// 格式化当前日期时间
    /// - Returns: 如 "2026年06月11日 14:30:25"
    private static func formatDateTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        return formatter.string(from: Date())
    }
}
