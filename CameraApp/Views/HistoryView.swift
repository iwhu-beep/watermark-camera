//
//  HistoryView.swift
//  CameraApp
//
//  历史记录浏览：日历视图 + CSV导出
//  路径: CameraApp/Views/HistoryView.swift
//

import SwiftUI

// MARK: - 历史记录页面

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var allRecords: [PhotoRecord] = []
    @State private var selectedDate: Date? = nil
    @State private var recordsByDate: [Date: [PhotoRecord]] = [:]
    @State private var showingRecords: [PhotoRecord] = []
    @State private var showExportSheet = false
    @State private var csvURL: URL?
    @State private var currentMonth: Date = Date()
    @State private var isReuploading = false
    @State private var reuploadMessage = ""
    @State private var reuploadProgress = 0

    private let calendar = Calendar.current

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 月份导航
                monthNavigator

                // 日历网格
                calendarGrid

                Divider()

                // 选中日期的记录列表
                if let date = selectedDate {
                    dateRecordsView(date: date)
                } else {
                    Spacer()
                    Text("选择日期查看拍摄记录")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        exportCSV()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(allRecords.isEmpty)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear { loadData() }
        .sheet(isPresented: $showExportSheet) {
            if let url = csvURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - 月份导航

    private var monthNavigator: some View {
        HStack {
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .padding()
            }

            Spacer()

            let formatter = DateFormatter()
            let _ = formatter.dateFormat = "yyyy年 M月"
            let _ = formatter.locale = Locale(identifier: "zh_CN")
            Text(formatter.string(from: currentMonth))
                .font(.headline)

            Spacer()

            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .padding()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 日历网格

    private var calendarGrid: some View {
        let daysInMonth = getDaysInMonth(for: currentMonth)
        let firstWeekday = getFirstWeekday(for: currentMonth)

        return VStack(spacing: 8) {
            // 星期标题
            HStack {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 日期网格
            let weeks = generateWeeks(daysInMonth: daysInMonth, firstWeekday: firstWeekday)
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let day = weeks[weekIndex][dayIndex]
                        if let day = day {
                            let date = calendar.date(from: DateComponents(
                                year: calendar.component(.year, from: currentMonth),
                                month: calendar.component(.month, from: currentMonth),
                                day: day
                            )) ?? Date()
                            let hasRecords = recordsByDate[calendar.startOfDay(for: date)] != nil
                            let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                            let isToday = calendar.isDateInToday(date)

                            ZStack {
                                Circle()
                                    .fill(isSelected ? Color.blue : (isToday ? Color.blue.opacity(0.2) : Color.clear))
                                    .frame(width: 36, height: 36)

                                VStack(spacing: 2) {
                                    Text("\(day)")
                                        .font(.system(size: 14))
                                        .foregroundColor(isSelected ? .white : .primary)

                                    if hasRecords {
                                        Circle()
                                            .fill(isSelected ? Color.white : Color.blue)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                            }
                            .onTapGesture {
                                withAnimation {
                                    selectedDate = date
                                    showingRecords = recordsByDate[calendar.startOfDay(for: date)] ?? []
                                }
                            }
                        } else {
                            Color.clear.frame(width: 36, height: 36)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 日期记录列表

    private func dateRecordsView(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let formatter = DateFormatter()
            let _ = formatter.dateFormat = "M月d日 EEEE"
            let _ = formatter.locale = Locale(identifier: "zh_CN")

            HStack {
                Text(formatter.string(from: date))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(showingRecords.count) 个文件")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 重新上传按钮
            if !showingRecords.isEmpty && BaiduUploader.shared.isLoggedIn() {
                HStack {
                    if isReuploading {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("正在上传 (\(reuploadProgress)/\(showingRecords.count))")
                            .font(.caption)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("重新上传到百度网盘 (\(showingRecords.count) 个文件)")
                            .font(.caption)
                    }
                    Spacer()
                }
                .foregroundColor(.blue)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 4)
                .onTapGesture {
                    if !isReuploading {
                        reuploadRecords(showingRecords, date: date)
                    }
                }
                .disabled(isReuploading)
            }

            // 上传状态提示
            if !reuploadMessage.isEmpty {
                Text(reuploadMessage)
                    .font(.caption)
                    .foregroundColor(reuploadMessage.contains("成功") ? .green : .secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            if showingRecords.isEmpty {
                Text("当日无拍摄记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(showingRecords, id: \.id) { record in
                            RecordRow(record: record)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxHeight: 350)
        .background(Color(.systemGray6))
    }

    // MARK: - 数据加载

    private func loadData() {
        allRecords = PhotoStore.shared.getAllRecords()

        // 按日期分组
        var grouped: [Date: [PhotoRecord]] = [:]
        for record in allRecords {
            let day = calendar.startOfDay(for: record.date)
            grouped[day, default: []].append(record)
        }
        recordsByDate = grouped
    }

    // MARK: - 重新上传

    private func reuploadRecords(_ records: [PhotoRecord], date: Date) {
        guard !records.isEmpty else { return }

        isReuploading = true
        reuploadProgress = 0
        reuploadMessage = "开始上传..."

        // 构建日期文件夹
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateFolder = formatter.string(from: date)

        uploadNextRecord(records, index: 0, dateFolder: dateFolder)
    }

    private func uploadNextRecord(_ records: [PhotoRecord], index: Int, dateFolder: String) {
        guard index < records.count else {
            // 全部完成
            isReuploading = false
            reuploadMessage = "全部上传成功 (\(records.count) 个文件)"
            return
        }

        let record = records[index]
        let localURL = URL(fileURLWithPath: record.filePath)

        guard FileManager.default.fileExists(atPath: record.filePath) else {
            // 文件不存在，跳过
            reuploadMessage = "跳过: \(record.fileName) (文件不存在)"
            uploadNextRecord(records, index: index + 1, dateFolder: dateFolder)
            return
        }

        // 构建远程路径
        let folder: String
        if !record.note.isEmpty {
            let sanitizedNote = ZipUtility.sanitize(record.note)
            folder = "\(dateFolder)/\(sanitizedNote)"
        } else {
            folder = dateFolder
        }
        let remotePath = "/apps/拍照/\(folder)/\(record.fileName)"

        reuploadMessage = "正在上传: \(record.fileName)"
        reuploadProgress = index + 1

        BaiduUploader.shared.uploadFile(
            localURL: localURL,
            remotePath: remotePath,
            onSuccess: { [self] in
                // 延迟 0.5 秒后上传下一个，避免过快触发限流
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    uploadNextRecord(records, index: index + 1, dateFolder: dateFolder)
                }
            },
            onFailure: { [self] error in
                isReuploading = false
                reuploadMessage = "上传失败: \(error.localizedDescription)"
            }
        )
    }

    // MARK: - 日历辅助方法

    private func getDaysInMonth(for date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    private func getFirstWeekday(for date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        let firstDay = calendar.date(from: components)!
        return calendar.component(.weekday, from: firstDay) - 1 // 0-indexed
    }

    private func generateWeeks(daysInMonth: Int, firstWeekday: Int) -> [[Int?]] {
        var weeks: [[Int?]] = []
        var currentWeek: [Int?] = Array(repeating: nil, count: firstWeekday)

        for day in 1...daysInMonth {
            currentWeek.append(day)
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }

        // 补齐最后一周
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }

        return weeks
    }

    // MARK: - CSV 导出

    private func exportCSV() {
        guard !allRecords.isEmpty else { return }

        var csvContent = "日期,时间,文件名,类型,备注\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for record in allRecords.sorted(by: { $0.date < $1.date }) {
            let dateStr = dateFormatter.string(from: record.date)
            let timeStr = timeFormatter.string(from: record.date)
            let typeStr = record.isVideo ? "视频" : "图片"
            let note = record.note.replacingOccurrences(of: ",", with: "，")

            csvContent += "\(dateStr),\(timeStr),\(record.fileName),\(typeStr),\(note)\n"
        }

        // 写入临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "拍摄记录_\(formatter.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            // 使用 UTF-8 BOM 确保 Excel 正确识别中文
            let bom = Data([0xEF, 0xBB, 0xBF])
            let csvData = bom + (csvContent.data(using: .utf8) ?? Data())
            try csvData.write(to: fileURL)
            csvURL = fileURL
            showExportSheet = true
        } catch {
            print("[History] CSV导出失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - 记录行

struct RecordRow: View {
    let record: PhotoRecord

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: record.isVideo ? "video.fill" : "photo.fill")
                .foregroundColor(record.isVideo ? .red : .blue)
                .frame(width: 24)

            // 文件名
            VStack(alignment: .leading, spacing: 2) {
                Text(record.fileName)
                    .font(.subheadline)
                    .lineLimit(1)

                if !record.note.isEmpty {
                    Text(record.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 时间
            let formatter = DateFormatter()
            let _ = formatter.dateFormat = "HH:mm"
            Text(formatter.string(from: record.date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
