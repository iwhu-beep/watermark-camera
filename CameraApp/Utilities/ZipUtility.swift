//
//  ZipUtility.swift
//  CameraApp
//
//  ZIP 压缩工具：将照片文件压缩为 ZIP 包
//  路径: CameraApp/Utilities/ZipUtility.swift
//

import Foundation

/// ZIP 压缩工具类
struct ZipUtility {

    /// 将多个文件压缩为 ZIP
    /// - Parameters:
    ///   - filePaths: 文件路径数组
    ///   - zipName: ZIP 文件名（不含扩展名）
    /// - Returns: ZIP 文件 URL
    static func createZip(from filePaths: [String], zipName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent("\(sanitize(zipName)).zip")

        // 删除已存在的同名 ZIP
        try? FileManager.default.removeItem(at: zipURL)

        // 创建临时目录，将文件复制进去
        let stagingDir = tempDir.appendingPathComponent("zip_staging_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: stagingDir)
        }

        // 复制文件到临时目录
        for path in filePaths {
            let srcURL = URL(fileURLWithPath: path)
            let dstURL = stagingDir.appendingPathComponent(srcURL.lastPathComponent)
            try? FileManager.default.copyItem(at: srcURL, to: dstURL)
        }

        // 使用 SSZipArchive 或系统 API 压缩
        // iOS 没有内置 ZIP API，使用 Coordination + FileManager 的方式
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var zipError: Error?

        coordinator.coordinate(writingItemAt: stagingDir, options: .forUploading, error: &coordinatorError) { url in
            do {
                try FileManager.default.copyItem(at: url, to: zipURL)
            } catch {
                zipError = error
            }
        }

        if let error = coordinatorError ?? zipError {
            print("[ZipUtility] 压缩失败: \(error.localizedDescription)")
            return nil
        }

        return zipURL
    }

    /// 批量创建 ZIP（按备注分组）
    /// - Parameter groups: [备注名: [照片记录]]
    /// - Returns: [(备注名, ZIP URL)]
    static func createZips(from groups: [String: [PhotoRecord]]) -> [(String, URL)] {
        var results: [(String, URL)] = []

        for (note, records) in groups {
            let filePaths = records.map { $0.filePath }

            // 如果只有一个备注分组，直接用日期+备注名
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStr = formatter.string(from: Date())
            let zipName = "\(note)_\(dateStr)"

            if let zipURL = createZip(from: filePaths, zipName: zipName) {
                results.append((note, zipURL))
            }
        }

        return results
    }

    /// 清理临时 ZIP 文件
    static func cleanup(zipURLs: [URL]) {
        for url in zipURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 清理文件名中的非法字符
    private static func sanitize(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}
