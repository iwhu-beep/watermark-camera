//
//  UIImage+Orientation.swift
//  CameraApp
//
//  UIImage 方向修正扩展
//  路径: CameraApp/Utilities/UIImage+Orientation.swift
//

import UIKit

extension UIImage {
    /// 将图片旋转到指定方向（用于修正横屏拍摄时的方向问题）
    func rotateTo(orientation: UIImage.Orientation) -> UIImage {
        guard self.imageOrientation != orientation else { return self }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = normalizedImage?.cgImage else { return self }

        return UIImage(
            cgImage: cgImage,
            scale: scale,
            orientation: orientation
        )
    }

    /// 将图片方向标准化为 .up（消除旋转标记）
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        return rotateTo(orientation: .up)
    }
}
