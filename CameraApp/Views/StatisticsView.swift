//
//  StatisticsView.swift
//  CameraApp
//
//  拍摄统计页面：今日/本周/本月数量与容量统计
//  路径: CameraApp/Views/StatisticsView.swift
//

import SwiftUI

// MARK: - 统计数据

struct DailyStats: Identifiable {
    let id = UUID()
    let date: Date
    let photoCount: Int
    let videoCount: Int
    let totalSize: Int64

    var totalCount: Int { photoCount + videoCount }
}

// MARK: - 统计页面

struct StatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var allRecords: [PhotoRecord] = []
    @State private var dailyStats: [DailyStats] = []
    @State private var todayCount: Int = 0
    @State private var weekCount: Int = 0
    @State private var monthCount: Int = 0
    @State private var totalSize: Int64 = 0
    @State private var todaySize: Int64 = 0

    private let calendar = Calendar.current

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 概览卡片
                    overviewSection

                    // 最近7天柱状图
                    chartSection

                    // 详细列表
                    detailSection
                }
                .padding()
            }
            .navigationTitle("拍摄统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear {
            loadData()
        }
    }

    // MARK: - 概览卡片

    private var overviewSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "今日", count: todayCount, size: todaySize, color: .blue)
                StatCard(title: "本周", count: weekCount, size: nil, color: .green)
                StatCard(title: "本月", count: monthCount, size: nil, color: .orange)
            }

            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.gray)
                Text("本地总容量")
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatSize(totalSize))
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - 柱状图（最近7天）

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近 7 天")
                .font(.headline)

            let last7Days = dailyStats.suffix(7)
            let maxCount = last7Days.map { $0.totalCount }.max() ?? 1

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(last7Days.enumerated()), id: \.element.id) { index, stat in
                    VStack(spacing: 4) {
                        // 数量标签
                        Text("\(stat.totalCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // 柱子
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stat.totalCount > 0 ? Color.blue : Color.gray.opacity(0.2))
                            .frame(
                                width: 32,
                                height: max(4, CGFloat(stat.totalCount) / CGFloat(max(maxCount, 1)) * 100)
                            )

                        // 日期标签
                        let dayStr = formatDateShort(stat.date)
                        Text(dayStr)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }

    // MARK: - 详细列表

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史记录")
                .font(.headline)

            if dailyStats.isEmpty {
                Text("暂无拍摄记录")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(dailyStats.reversed(), id: \.id) { stat in
                    HStack {
                        Text(formatDateFull(stat.date))
                            .font(.subheadline)

                        Spacer()

                        if stat.photoCount > 0 {
                            Label("\(stat.photoCount)", systemImage: "photo")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        if stat.videoCount > 0 {
                            Label("\(stat.videoCount)", systemImage: "video")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Text(formatSize(stat.totalSize))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 6)

                    if stat.id != dailyStats.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 数据加载

    private func loadData() {
        allRecords = PhotoStore.shared.getAllRecords()

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: now) + 1, to: startOfToday) ?? startOfToday
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday

        // 统计各时间段
        todayCount = allRecords.filter { $0.date >= startOfToday }.count
        weekCount = allRecords.filter { $0.date >= startOfWeek }.count
        monthCount = allRecords.filter { $0.date >= startOfMonth }.count

        // 按日期分组统计
        var groupedByDate: [Date: [PhotoRecord]] = [:]
        for record in allRecords {
            let day = calendar.startOfDay(for: record.date)
            groupedByDate[day, default: []].append(record)
        }

        // 计算每天的数据
        var stats: [DailyStats] = []
        for (day, records) in groupedByDate.sorted(by: { $0.key < $1.key }) {
            let photos = records.filter { !$0.isVideo }.count
            let videos = records.filter { $0.isVideo }.count
            let size = records.reduce(Int64(0)) { total, record in
                if let attrs = try? FileManager.default.attributesOfItem(atPath: record.filePath),
                   let fileSize = attrs[.size] as? Int64 {
                    return total + fileSize
                }
                return total
            }
            stats.append(DailyStats(date: day, photoCount: photos, videoCount: videos, totalSize: size))
        }
        dailyStats = stats

        // 计算容量
        totalSize = allRecords.reduce(Int64(0)) { total, record in
            if let attrs = try? FileManager.default.attributesOfItem(atPath: record.filePath),
               let fileSize = attrs[.size] as? Int64 {
                return total + fileSize
            }
            return total
        }

        todaySize = allRecords.filter { $0.date >= startOfToday }.reduce(Int64(0)) { total, record in
            if let attrs = try? FileManager.default.attributesOfItem(atPath: record.filePath),
               let fileSize = attrs[.size] as? Int64 {
                return total + fileSize
            }
            return total
        }
    }

    // MARK: - 格式化

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func formatDateFull(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - 统计卡片

struct StatCard: View {
    let title: String
    let count: Int
    let size: Int64?
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text("张")
                .font(.caption2)
                .foregroundColor(.secondary)

            if let size = size {
                let formatter = ByteCountFormatter()
                let _ = formatter.allowedUnits = [.useKB, .useMB]
                let _ = formatter.countStyle = .file
                Text(formatter.string(fromByteCount: size))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}
