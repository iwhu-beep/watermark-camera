//
//  ZipUtility.swift
//  CameraApp
//
//  照片打包工具：按备注分组整理照片文件
//  路径: CameraApp/Utilities/ZipUtility.swift
//

import Foundation

/// 照片打包工具类（iOS 无内置 ZIP API，直接返回文件数据）
struct ZipUtility {

    /// 按备注分组获取照片附件数据
    /// - Parameter groups: [备注名: [照片记录]]
    /// - Returns: 邮件附件数组
    static func prepareAttachments(from groups: [String: [PhotoRecord]]) -> [(data: Data, mimeType: String, fileName: String)] {
        var attachments: [(data: Data, mimeType: String, fileName: String)] = []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())

        for (note, records) in groups {
            for (index, record) in records.enumerated() {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: record.filePath)) else {
                    continue
                }

                let ext = record.isVideo ? "mp4" : "jpg"
                let mimeType = record.isVideo ? "video/mp4" : "image/jpeg"
                // 文件名: 备注_日期_序号.jpg
                let fileName = "\(sanitize(note))_\(dateStr)_\(index + 1).\(ext)"

                attachments.append((data: data, mimeType: mimeType, fileName: fileName))
            }
        }

        return attachments
    }

    /// 清理临时文件
    static func cleanup(zipURLs: [URL]) {
        for url in zipURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 清理文件名中的非法字符
    private static func sanitize(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalidChars).joined(separator: "_")
        return cleaned.isEmpty ? "photo" : cleaned
    }
}
