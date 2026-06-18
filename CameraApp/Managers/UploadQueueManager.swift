//
//  UploadQueueManager.swift
//  CameraApp
//
//  离线上传队列：无网络时保存任务，有网后自动上传
//  路径: CameraApp/Managers/UploadQueueManager.swift
//

import Foundation
import Network

// MARK: - 上传任务

/// 待上传任务
struct UploadTask: Codable, Identifiable {
    let id: UUID
    let localPath: String
    let fileName: String
    let note: String
    let date: Date
    let isVideo: Bool

    init(localPath: String, fileName: String, note: String, isVideo: Bool) {
        self.id = UUID()
        self.localPath = localPath
        self.fileName = fileName
        self.note = note
        self.date = Date()
        self.isVideo = isVideo
    }
}

// MARK: - 上传队列管理器

/// 管理离线上传队列，监听网络状态自动上传
final class UploadQueueManager: NSObject, ObservableObject {

    static let shared = UploadQueueManager()

    /// 队列中的待上传任务数
    @Published private(set) var pendingCount: Int = 0

    /// 是否正在上传
    @Published private(set) var isUploading: Bool = false

    /// 当前是否有网络
    @Published private(set) var isNetworkAvailable: Bool = true

    private let defaults = UserDefaults.standard
    private let queueKey = "uploadQueueTasks"
    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "UploadQueueMonitor")
    private var tasks: [UploadTask] = []
    private var isProcessing = false

    private override init() {
        pathMonitor = NWPathMonitor()
        super.init()

        loadTasks()
        updatePendingCount()
        startMonitoring()

        // App 进入前台时也尝试处理队列
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        pathMonitor.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 网络监听

    private func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let available = path.status == .satisfied
                self?.isNetworkAvailable = available
                print("[UploadQueue] 网络状态: \(available ? "可用" : "不可用")")

                if available && !(self?.tasks.isEmpty ?? true) {
                    self?.processQueue()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    @objc private func appDidBecomeActive() {
        if isNetworkAvailable && !tasks.isEmpty {
            processQueue()
        }
    }

    // MARK: - 添加任务

    /// 将文件加入上传队列
    /// - Parameters:
    ///   - localPath: 本地文件路径
    ///   - fileName: 文件名
    ///   - note: 备注（用于分文件夹）
    ///   - isVideo: 是否为视频
    func enqueue(localPath: String, fileName: String, note: String, isVideo: Bool) {
        let task = UploadTask(localPath: localPath, fileName: fileName, note: note, isVideo: isVideo)
        tasks.append(task)
        saveTasks()
        updatePendingCount()
        print("[UploadQueue] 已加入队列: \(fileName), 当前待上传: \(tasks.count)")

        // 如果有网络立即上传
        if isNetworkAvailable {
            processQueue()
        }
    }

    /// 将 UIImage 保存后加入队列
    func enqueueImage(_ image: UIImage, fileName: String, note: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let queueDir = docs.appendingPathComponent("UploadQueue", isDirectory: true)
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        let fileURL = queueDir.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }

        do {
            try data.write(to: fileURL)
            enqueue(localPath: fileURL.path, fileName: fileName, note: note, isVideo: false)
        } catch {
            print("[UploadQueue] 保存图片到队列失败: \(error.localizedDescription)")
        }
    }

    /// 将视频文件复制后加入队列
    func enqueueVideo(from sourceURL: URL, fileName: String, note: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let queueDir = docs.appendingPathComponent("UploadQueue", isDirectory: true)
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        let fileURL = queueDir.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: fileURL)
            enqueue(localPath: fileURL.path, fileName: fileName, note: note, isVideo: true)
        } catch {
            print("[UploadQueue] 复制视频到队列失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 处理队列

    private func processQueue() {
        guard !isProcessing, isNetworkAvailable, !tasks.isEmpty else { return }
        isProcessing = true
        isUploading = true

        processNextTask()
    }

    private func processNextTask() {
        guard !tasks.isEmpty else {
            isProcessing = false
            isUploading = false
            print("[UploadQueue] 队列已全部上传完成")
            return
        }

        let task = tasks[0]
        let localURL = URL(fileURLWithPath: task.localPath)

        guard FileManager.default.fileExists(atPath: task.localPath) else {
            print("[UploadQueue] 文件不存在，跳过: \(task.fileName)")
            tasks.removeFirst()
            saveTasks()
            updatePendingCount()
            processNextTask()
            return
        }

        // 构建远程路径：按日期分文件夹
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateFolder = formatter.string(from: task.date)

        // 如果有备注，在日期文件夹下再分一层
        let remotePath: String
        if !task.note.isEmpty {
            let sanitizedNote = ZipUtility.sanitize(task.note)
            remotePath = "/apps/拍照/\(dateFolder)/\(sanitizedNote)/\(task.fileName)"
        } else {
            remotePath = "/apps/拍照/\(dateFolder)/\(task.fileName)"
        }

        print("[UploadQueue] 正在上传: \(task.fileName) → \(remotePath)")

        BaiduUploader.shared.uploadFile(
            localURL: localURL,
            remotePath: remotePath,
            onProgress: nil,
            onSuccess: { [weak self] in
                print("[UploadQueue] 上传成功: \(task.fileName)")
                // 删除本地队列文件
                try? FileManager.default.removeItem(at: localURL)
                self?.tasks.removeFirst()
                self?.saveTasks()
                self?.updatePendingCount()

                // 延迟 1 秒后上传下一个，避免过快触发限流
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.processNextTask()
                }
            },
            onFailure: { [weak self] error in
                print("[UploadQueue] 上传失败: \(task.fileName), 错误: \(error.localizedDescription)")

                // 网络错误保留任务等待重试，其他错误移除任务
                if case .networkError = error {
                    self?.isProcessing = false
                    self?.isUploading = false
                } else {
                    // 授权失败或文件错误，移除任务
                    try? FileManager.default.removeItem(at: localURL)
                    self?.tasks.removeFirst()
                    self?.saveTasks()
                    self?.updatePendingCount()
                    self?.processNextTask()
                }
            }
        )
    }

    // MARK: - 持久化

    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: queueKey)
        }
    }

    private func loadTasks() {
        guard let data = defaults.data(forKey: queueKey),
              let loaded = try? JSONDecoder().decode([UploadTask].self, from: data) else { return }
        tasks = loaded
    }

    private func updatePendingCount() {
        pendingCount = tasks.count
    }

    // MARK: - 清空队列

    /// 清空所有待上传任务
    func clearQueue() {
        // 删除队列目录中的文件
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let queueDir = docs.appendingPathComponent("UploadQueue", isDirectory: true)
        try? FileManager.default.removeItem(at: queueDir)

        tasks.removeAll()
        saveTasks()
        updatePendingCount()
        print("[UploadQueue] 队列已清空")
    }

    /// 获取所有待上传任务（用于显示）
    func getPendingTasks() -> [UploadTask] {
        return tasks
    }
}
