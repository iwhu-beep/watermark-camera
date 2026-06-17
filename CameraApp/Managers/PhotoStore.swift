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
        let fileName = videoURL.lastPathComponent
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

    // MARK: - 私有方法

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
