//
//  ImageWatermark.swift
//  CameraApp
//
//  独立水印绘制工具类：在图片左下角绘制信息面板
//  路径: CameraApp/Utilities/ImageWatermark.swift
//

import UIKit

/// 独立图片水印工具类
/// 在图片左下角绘制半透明信息面板，显示经纬度、坐标、地址、时间、备注
struct ImageWatermark {

    // MARK: - 常量

    /// 基准设计宽度（以1000px为参考）
    private static let referenceWidth: CGFloat = 1000

    /// 基准边距（距图片边缘）
    private static let baseMargin: CGFloat = 24

    /// 基准内边距（面板内部）
    private static let basePadding: CGFloat = 16

    /// 基准圆角
    private static let baseCornerRadius: CGFloat = 10

    /// 行间距
    private static let baseLineSpacing: CGFloat = 6

    // MARK: - 公开接口

    /// 在图片左下角绘制信息面板水印
    ///
    /// - Parameters:
    ///   - image: 原始照片
    ///   - lines: 水印文本行数组，如 ["经度: 116.407", "纬度: 39.904", ...]
    ///   - fontSizeScale: 字号缩放倍数
    ///   - verticalPosition: 垂直位置（0=底部, 0.5=居中, 1=顶部）
    /// - Returns: 添加水印后的新UIImage
    static func draw(
        on image: UIImage,
        lines: [String],
        fontSizeScale: CGFloat = 1.0,
        verticalPosition: Double = 0.0
    ) -> UIImage {

        guard !lines.isEmpty else { return image }

        let imgWidth = image.size.width
        let imgHeight = image.size.height
        let scale = imgWidth / referenceWidth

        // 计算各尺寸
        let fontSize = 28 * scale * fontSizeScale
        let margin = baseMargin * scale
        let padding = basePadding * scale
        let cornerRadius = baseCornerRadius * scale
        let lineSpacing = baseLineSpacing * scale
        let strokeWidth = 1.5 * scale

        // 文字属性
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: UIColor.white.opacity(0.8),
            .strokeColor: UIColor.black,
            .strokeWidth: -strokeWidth * 0.5
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -strokeWidth * 0.5
        ]

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(at: .zero)

            // 计算每行尺寸
            var lineSizes: [(label: CGSize, value: CGSize, full: CGSize)] = []
            var maxWidth: CGFloat = 0
            var totalHeight: CGFloat = 0

            for (i, line) in lines.enumerated() {
                // 拆分标签和值
                let parts = splitLabelValue(line)
                let labelSize = parts.label.size(withAttributes: labelAttrs)
                let valueSize = parts.value.size(withAttributes: valueAttrs)
                let fullSize = line.size(withAttributes: valueAttrs)
                lineSizes.append((labelSize, valueSize, fullSize))
                maxWidth = max(maxWidth, fullSize.width)
                totalHeight += fullSize.height
                if i < lines.count - 1 {
                    totalHeight += lineSpacing
                }
            }

            // 面板尺寸
            let panelWidth = maxWidth + padding * 2
            let panelHeight = totalHeight + padding * 2

            // 面板位置（左下角）
            let panelX = margin
            let availableY = imgHeight - margin * 2 - panelHeight
            let panelY = margin + availableY * CGFloat(1.0 - verticalPosition)

            // 绘制半透明背景面板
            let panelRect = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
            let bgPath = UIBezierPath(roundedRect: panelRect, cornerRadius: cornerRadius)
            UIColor.black.withAlphaComponent(0.55).setFill()
            bgPath.fill()

            // 绘制文字行
            var currentY = panelY + padding

            for (i, line) in lines.enumerated() {
                let parts = splitLabelValue(line)
                var currentX = panelX + padding

                // 绘制标签部分
                parts.label.draw(
                    at: CGPoint(x: currentX, y: currentY),
                    withAttributes: labelAttrs
                )
                currentX += lineSizes[i].label.width

                // 绘制值部分
                parts.value.draw(
                    at: CGPoint(x: currentX, y: currentY),
                    withAttributes: valueAttrs
                )

                currentY += lineSizes[i].full.height
                if i < lines.count - 1 {
                    currentY += lineSpacing
                }
            }
        }
    }

    // MARK: - 私有工具

    /// 拆分 "标签：值" 格式文本
    private static func splitLabelValue(_ text: String) -> (label: String, value: String) {
        // 支持中文冒号和英文冒号
        if let range = text.range(of: "：") {
            let label = String(text[..<range.upperBound])
            let value = String(text[range.upperBound...])
            return (label, value)
        } else if let range = text.range(of: ":") {
            let label = String(text[..<range.upperBound])
            let value = String(text[range.upperBound...])
            return (label, value)
        }
        return ("", text)
    }
}
