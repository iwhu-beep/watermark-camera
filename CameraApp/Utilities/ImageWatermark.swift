//
//  ImageWatermark.swift
//  CameraApp
//
//  独立水印绘制工具类：输入UIImage+经纬度+备注，输出水印新图
//  路径: CameraApp/Utilities/ImageWatermark.swift
//

import UIKit

/// 独立图片水印工具类，无外部依赖，可直接调用
struct ImageWatermark {

    // MARK: - 常量

    /// 基准设计宽度（以1000px为参考，所有尺寸按此缩放）
    private static let referenceWidth: CGFloat = 1000

    /// 基准字体大小（在1000px宽图片上的字号）
    private static let baseFontSize: CGFloat = 28

    /// 基准边距（在1000px宽图片上距边缘20pt）
    private static let baseMargin: CGFloat = 20

    /// 基准描边宽度（在1000px宽图片上1pt黑色描边）
    private static let baseStrokeWidth: CGFloat = 1.5

    /// 行间距倍数（相对字体大小）
    private static let lineSpacingRatio: CGFloat = 0.35

    // MARK: - 公开接口

    /// 在图片上绘制水印，返回新UIImage（不修改原图）
    ///
    /// - Parameters:
    ///   - image: 原始照片
    ///   - coordinate: 经纬度文本
    ///   - note: 备注文本，为空则只绘制坐标和时间
    ///   - fontSizeScale: 字号缩放倍数（1.0为基准大小，2.0为两倍大）
    ///   - verticalPosition: 垂直位置（0=底部, 0.5=居中, 1=顶部）
    /// - Returns: 添加水印后的新UIImage
    static func draw(
        on image: UIImage,
        coordinate: String,
        note: String? = nil,
        fontSizeScale: CGFloat = 1.0,
        verticalPosition: Double = 0.15
    ) -> UIImage {

        let imgWidth = image.size.width
        let imgHeight = image.size.height

        // 按图片宽度相对参考宽度计算缩放因子
        let scale = imgWidth / referenceWidth

        // 缩放后实际尺寸（再乘以用户设置的字号倍数）
        let fontSize = baseFontSize * scale * fontSizeScale
        let margin = baseMargin * scale
        let strokeWidth = baseStrokeWidth * scale
        let lineSpacing = fontSize * lineSpacingRatio

        // 文字属性：白色填充 + 黑色描边
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

            // 计算水印总高度
            var totalHeight: CGFloat = 0
            let line1Size = coordinate.size(withAttributes: textAttributes)
            totalHeight += line1Size.height
            let line2Size = dateTimeText.size(withAttributes: textAttributes)
            totalHeight += line2Size.height + lineSpacing
            if let note = note, !note.isEmpty {
                let noteSize = note.size(withAttributes: textAttributes)
                totalHeight += noteSize.height + lineSpacing
            }

            // 根据 verticalPosition 计算起始Y坐标
            // 0 = 底部（margin上方），0.5 = 居中，1 = 顶部
            let availableSpace = imgHeight - margin * 2 - totalHeight
            let startY = margin + availableSpace * CGFloat(1.0 - verticalPosition)

            var currentY = startY

            // 第一行（顶部）：备注
            if let note = note, !note.isEmpty {
                note.draw(
                    at: CGPoint(x: margin, y: currentY),
                    withAttributes: textAttributes
                )
                currentY += note.size(withAttributes: textAttributes).height + lineSpacing
            }

            // 第二行：日期时间
            dateTimeText.draw(
                at: CGPoint(x: margin, y: currentY),
                withAttributes: textAttributes
            )
            currentY += line2Size.height + lineSpacing

            // 第三行（底部）：经纬度坐标
            coordinate.draw(
                at: CGPoint(x: margin, y: currentY),
                withAttributes: textAttributes
            )
        }
    }

    // MARK: - 私有工具

    /// 格式化当前日期时间
    private static func formatDateTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        return formatter.string(from: Date())
    }
}
