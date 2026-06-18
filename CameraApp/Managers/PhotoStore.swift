//
//  PhotoStore.swift
//  CameraApp
//
//  照片记录管理器：保存拍照副本到本地，按日期和备注分组管理
//  路径: CameraApp/Managers/PhotoStore.swift
//

import Foundation
import UIKit

// MARK: - 照片记录

/// 单条照片记录
struct PhotoRecord: Codable, Identifiable {
    let id: UUID
    let filePath: String
    let note: String
    let date: Date
    let isVideo: Bool

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }
}

// MARK: - 照片存储管理器

/// 管理拍照后的本地副本和元数据
final class PhotoStore: ObservableObject {

    static let shared = PhotoStore()

    /// 当天照片数量
    @Published private(set) var todayPhotoCount: Int = 0

    private let defaults = UserDefaults.standard
    private let recordsKey = "photoRecords"
    private let photosDir: URL

    private init() {
        // 在 Documents 目录下创建 Photos 子目录
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        photosDir = docs.appendingPathComponent("Photos", isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        // 统计当天照片数
        refreshTodayCount()
    }

    // MARK: - 保存照片

    /// 保存照片副本到本地
    /// - Parameters:
    ///   - image: 照片 UIImage
    ///   - note: 备注内容
    ///   - fileName: 文件名（如 IMG_xxx.jpg）
    func savePhoto(image: UIImage, note: String, fileName: String) {
        let fileURL = photosDir.appendingPathComponent(fileName)

        // 保存 JPEG（质量 0.9 节省空间）
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }

        do {
            try data.write(to: fileURL)

            let record = PhotoRecord(
                id: UUID(),
                filePath: fileURL.path,
                note: note,
                date: Date(),
                isVideo: false
            )

            addRecord(record)
            refreshTodayCount()
            print("[PhotoStore] 已保存照片: \(fileName), 备注: \(note)")
        } catch {
            print("[PhotoStore] 保存照片失败: \(error.localizedDescription)")
        }
    }

    /// 保存视频副本到本地
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - note: 备注内容
    func saveVideo(from videoURL: URL, note: String) {
        // 使用备注内容作为文件名前缀
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let prefix = note.isEmpty ? "VID" : note
        let fileName = "\(prefix)_\(formatter.string(from: Date())).mp4"
        let destURL = photosDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: videoURL, to: destURL)

            let record = PhotoRecord(
                id: UUID(),
                filePath: destURL.path,
                note: note,
                date: Date(),
                isVideo: true
            )

            addRecord(record)
            refreshTodayCount()
            print("[PhotoStore] 已保存视频: \(fileName), 备注: \(note)")
        } catch {
            print("[PhotoStore] 保存视频失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 查询

    /// 获取今天所有照片记录
    func getTodayRecords() -> [PhotoRecord] {
        let calendar = Calendar.current
        return getAllRecords().filter { calendar.isDateInToday($0.date) }
    }

    /// 按备注名分组获取今天的照片
    /// - Returns: [备注名: [照片记录]]
    func getTodayGroupedByNote() -> [String: [PhotoRecord]] {
        let records = getTodayRecords()
        var groups: [String: [PhotoRecord]] = [:]

        for record in records {
            let key = record.note.isEmpty ? "未命名" : record.note
            groups[key, default: []].append(record)
        }

        return groups
    }

    /// 获取所有记录
    func getAllRecords() -> [PhotoRecord] {
        guard let data = defaults.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([PhotoRecord].self, from: data) else {
            return []
        }
        return records
    }

    // MARK: - 清理

    /// 删除指定日期的照片文件和记录
    func deleteRecords(for date: Date) {
        let calendar = Calendar.current
        var records = getAllRecords()
        let toDelete = records.filter { calendar.isDate($0.date, inSameDayAs: date) }

        // 删除文件
        for record in toDelete {
            try? FileManager.default.removeItem(atPath: record.filePath)
        }

        // 移除记录
        records.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
        saveRecords(records)
        refreshTodayCount()
    }

    /// 删除超过指定天数的旧照片
    func cleanOldRecords(olderThanDays days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var records = getAllRecords()
        let toDelete = records.filter { $0.date < cutoff }

        for record in toDelete {
            try? FileManager.default.removeItem(atPath: record.filePath)
        }

        records.removeAll { $0.date < cutoff }
        saveRecords(records)
        refreshTodayCount()
    }

    /// 计算缓存大小（字节）：包括 Photos 目录 + 临时目录中的 ZIP/VID 文件
    func cacheSize() -> Int64 {
        var totalSize: Int64 = 0

        // Photos 目录大小
        totalSize += directorySize(at: photosDir)

        // 临时目录中的 ZIP 和 VID_*.mp4 文件
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                let name = file.lastPathComponent
                if name.hasSuffix(".zip") || (name.hasPrefix("VID_") && name.hasSuffix(".mp4")) {
                    if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(size)
                    }
                }
                // ZIP 压缩临时目录
                if name.hasPrefix("zip_staging_") {
                    totalSize += directorySize(at: file)
                }
            }
        }

        return totalSize
    }

    /// 格式化缓存大小为可读字符串
    func formattedCacheSize() -> String {
        let bytes = cacheSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 清理所有缓存：删除所有照片副本、临时 ZIP、临时视频、ZIP staging 目录
    func clearAllCache() {
        // 1. 清空 Photos 目录中的文件
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // 2. 清空记录
        saveRecords([])

        // 3. 清理临时目录中的 ZIP、VID、staging 目录
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files {
                let name = file.lastPathComponent
                if name.hasSuffix(".zip") || name.hasPrefix("VID_") || name.hasPrefix("zip_staging_") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }

        refreshTodayCount()
        print("[PhotoStore] 缓存已清理")
    }

    // MARK: - 私有方法

    /// 计算目录总大小
    private func directorySize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                  let isDir = values.isDirectory else { continue }
            if !isDir, let size = values.fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    private func addRecord(_ record: PhotoRecord) {
        var records = getAllRecords()
        records.append(record)
        saveRecords(records)
    }

    private func saveRecords(_ records: [PhotoRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: recordsKey)
        }
    }

    private func refreshTodayCount() {
        DispatchQueue.main.async {
            self.todayPhotoCount = self.getTodayRecords().count
        }
    }
}
