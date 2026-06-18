//
//  ZipUtility.swift
//  CameraApp
//
//  ZIP 压缩工具：使用 ZIPFoundation 创建真正的 ZIP 文件
//  路径: CameraApp/Utilities/ZipUtility.swift
//

import Foundation
import ZIPFoundation

/// ZIP 压缩工具类
struct ZipUtility {

    /// 按备注前缀分组创建 ZIP 压缩包
    /// 备注前 2 个字相同的归入同一个压缩包
    /// - Parameter groups: [备注名: [照片记录]]
    /// - Returns: [(分组名, ZIP文件URL)]
    static func createZips(from groups: [String: [PhotoRecord]]) -> [(String, URL)] {
        var results: [(String, URL)] = []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())

        // 按备注前 2 个字合并分组
        var mergedGroups: [String: [PhotoRecord]] = [:]
        for (note, records) in groups {
            let prefix = String(note.prefix(2))
            mergedGroups[prefix, default: []].append(contentsOf: records)
        }

        for (prefix, records) in mergedGroups {
            let zipName = "\(sanitize(prefix))_\(dateStr).zip"
            let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)

            // 删除已存在的同名文件
            try? FileManager.default.removeItem(at: zipURL)

            do {
                try FileManager.default.zipItems(records: records, to: zipURL)
                results.append((prefix, zipURL))
                print("[ZipUtility] 已创建 ZIP: \(zipName), 包含 \(records.count) 个文件")
            } catch {
                print("[ZipUtility] 创建 ZIP 失败: \(error.localizedDescription)")
            }
        }

        return results
    }

    /// 将所有记录合并为单个 ZIP 压缩包
    /// - Parameter records: 照片记录数组
    /// - Returns: ZIP 文件 URL
    static func createSingleZip(from records: [PhotoRecord]) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())

        let zipName = "打卡相机_\(dateStr).zip"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)

        // 删除已存在的同名文件
        try? FileManager.default.removeItem(at: zipURL)

        do {
            try FileManager.default.zipItems(records: records, to: zipURL)
            print("[ZipUtility] 已创建单个 ZIP: \(zipName), 包含 \(records.count) 个文件")
            return zipURL
        } catch {
            print("[ZipUtility] 创建 ZIP 失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 清理临时 ZIP 文件
    static func cleanup(zipURLs: [URL]) {
        for url in zipURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 清理文件名中的非法字符
    static func sanitize(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalidChars).joined(separator: "_")
        return cleaned.isEmpty ? "photo" : cleaned
    }
}

// MARK: - FileManager 扩展

extension FileManager {
    /// 将多条照片/视频记录压缩为 ZIP（保留原始文件名）
    func zipItems(records: [PhotoRecord], to destinationURL: URL) throws {
        // 创建临时目录
        let stagingDir = temporaryDirectory.appendingPathComponent("zip_staging_\(UUID().uuidString)", isDirectory: true)
        try createDirectory(at: stagingDir, withIntermediateDirectories: true)

        defer {
            try? removeItem(at: stagingDir)
        }

        // 复制文件到临时目录，使用原始文件名
        // 用 Set 跟踪已用文件名，避免同名冲突
        var usedNames: Set<String> = []

        for record in records {
            let srcURL = URL(fileURLWithPath: record.filePath)
            var fileName = record.fileName

            // 避免同名文件覆盖
            if usedNames.contains(fileName) {
                let ext = (fileName as NSString).pathExtension
                let base = (fileName as NSString).deletingPathExtension
                var counter = 2
                while usedNames.contains("\(base)_\(counter).\(ext)") {
                    counter += 1
                }
                fileName = "\(base)_\(counter).\(ext)"
            }
            usedNames.insert(fileName)

            let dstURL = stagingDir.appendingPathComponent(fileName)

            // 检查源文件是否存在
            if fileExists(atPath: record.filePath) {
                do {
                    try copyItem(at: srcURL, to: dstURL)
                    print("[ZipUtility] 已复制: \(fileName) (\(record.isVideo ? "视频" : "图片"))")
                } catch {
                    print("[ZipUtility] 复制失败: \(fileName), 错误: \(error.localizedDescription)")
                }
            } else {
                print("[ZipUtility] 源文件不存在: \(record.filePath)")
            }
        }

        // 使用 ZIPFoundation 创建 ZIP
        try zipItem(at: stagingDir, to: destinationURL)
    }
}
