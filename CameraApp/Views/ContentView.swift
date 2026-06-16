//
//  ContentView.swift
//  CameraApp
//
//  主界面：全屏取景 + 实时信息叠加 + 拍照/录像模式切换
//  路径: CameraApp/Views/ContentView.swift
//

import AVFoundation
import Photos
import SwiftUI

struct ContentView: View {

    // MARK: - 环境依赖

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissionManager: PermissionManager

    // MARK: - 状态对象

    @StateObject private var camera = CameraController()

    // MARK: - UI状态

    @State private var noteText: String = ""
    @State private var isCapturing: Bool = false
    @State private var showSettings: Bool = false
    @State private var showLocationPermissionAlert: Bool = false
    @State private var showUploadResult: Bool = false
    @State private var uploadResultMessage: String = ""
    @State private var showNoteInput: Bool = false
    @State private var recordingStartTime: Date? = nil

    // 自定义时间
    @State private var useCustomTime: Bool = false
    @State private var customTime: Date = Date()
    @State private var showTimePicker: Bool = false

    // 自定义经纬度
    @State private var useCustomCoord: Bool = false
    @State private var customLongitude: Double = 116.407400
    @State private var customLatitude: Double = 39.904200
    @State private var customAddress: String = ""
    @State private var showCoordPicker: Bool = false

    // 延迟拍摄
    @State private var delaySeconds: Int = 0
    @State private var countdownRemaining: Int = 0
    @State private var isCountingDown: Bool = false

    // 实时定位数据
    @State private var currentLongitude: String = "---"
    @State private var currentLatitude: String = "---"
    @State private var currentAddress: String = "定位中..."

    // 相机模式
    @State private var cameraMode: CameraMode = .photo

    // MARK: - 视图主体

    var body: some View {
        ZStack {
            // 全屏相机预览
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            VStack {
                topToolBar

                // 倒计时显示
                if isCountingDown {
                    countdownOverlay
                        .transition(.scale.combined(with: .opacity))
                }

                // 录像指示器
                if camera.isRecording {
                    recordingIndicator
                        .transition(.opacity)
                }

                Spacer()
                infoOverlay
                modeSwitchBar
                bottomControlBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                permissionManager.requestPermissions()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                camera.setupCamera()
                camera.onPhotoCaptured = handleCapturedPhoto
                camera.onVideoRecorded = handleVideoRecorded
                camera.watermarkFontSizeScale = settings.watermarkFontSize / 24.0
                camera.watermarkVerticalPosition = settings.watermarkVerticalPosition
                camera.watermarkProvider = { [self] in
                    return buildWatermarkText()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                startLocationUpdates()
            }
        }
        .onDisappear {
            camera.stopCamera()
            if camera.isRecording { camera.stopRecording() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings)
        }
        .alert("上传结果", isPresented: $showUploadResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(uploadResultMessage)
        }
        .alert("需要定位权限", isPresented: $showLocationPermissionAlert) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("请在系统设置中开启精确定位权限")
        }
    }

    // MARK: - 倒计时显示

    private var countdownOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: 100, height: 100)
            Text("\(countdownRemaining)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.top, 20)
    }

    // MARK: - 录像指示器

    private var recordingIndicator: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let duration = recordingStartTime.map {
                Int(context.date.timeIntervalSince($0))
            } ?? 0
            let minutes = duration / 60
            let seconds = duration % 60
            let timeStr = String(format: "%02d:%02d", minutes, seconds)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text("REC \(timeStr)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .padding(.top, 8)
        }
    }

    // MARK: - 顶部工具栏

    private var topToolBar: some View {
        HStack {
            // 设置
            Button(action: { showSettings = true }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // 延迟拍摄选择
            Menu {
                Button(action: { delaySeconds = 0 }) {
                    HStack {
                        Text("关闭")
                        if delaySeconds == 0 { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { delaySeconds = 3 }) {
                    HStack {
                        Text("3秒")
                        if delaySeconds == 3 { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { delaySeconds = 5 }) {
                    HStack {
                        Text("5秒")
                        if delaySeconds == 5 { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { delaySeconds = 10 }) {
                    HStack {
                        Text("10秒")
                        if delaySeconds == 10 { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .medium))
                    if delaySeconds > 0 {
                        Text("\(delaySeconds)s")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundColor(delaySeconds > 0 ? .yellow : .white)
                .frame(width: 50, height: 44)
            }

            // 闪光灯
            Button(action: { camera.cycleFlashMode() }) {
                Image(systemName: camera.flashMode.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            // 切换摄像头
            Button(action: { camera.switchCamera() }) {
                Image(systemName: "camera.rotate.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .background(
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - 信息叠加层

    private var infoOverlay: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let timeStr = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                if useCustomTime {
                    return f.string(from: customTime) + " (自定义)"
                } else {
                    return f.string(from: context.date)
                }
            }()

            VStack(alignment: .leading, spacing: 6) {
                // 经度行（可自定义）
                HStack(spacing: 4) {
                    Text("经度：")
                        .foregroundColor(.white.opacity(0.8))
                    Text(useCustomCoord ? String(format: "%.6f", customLongitude) : currentLongitude)
                        .foregroundColor(useCustomCoord ? .green : .white)
                        .lineLimit(1)
                }
                .font(.system(size: 15, weight: .medium))

                // 纬度行（可自定义）
                HStack(spacing: 4) {
                    Text("纬度：")
                        .foregroundColor(.white.opacity(0.8))
                    Text(useCustomCoord ? String(format: "%.6f", customLatitude) : currentLatitude)
                        .foregroundColor(useCustomCoord ? .green : .white)
                        .lineLimit(1)
                }
                .font(.system(size: 15, weight: .medium))

                infoRow(label: "坐标", value: "WGS84 坐标系")

                // 地址行
                HStack(spacing: 4) {
                    Text("地址：")
                        .foregroundColor(.white.opacity(0.8))
                    if useCustomCoord && !customAddress.isEmpty {
                        Text(customAddress)
                            .foregroundColor(.green)
                            .lineLimit(1)
                    } else {
                        Text(currentAddress)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: { showCoordPicker = true }) {
                        Image(systemName: useCustomCoord ? "location.fill" : "location")
                            .font(.system(size: 14))
                            .foregroundColor(useCustomCoord ? .green : .white.opacity(0.7))
                    }
                }
                .font(.system(size: 15, weight: .medium))

                // 时间行（可点击设置自定义时间）
                HStack(spacing: 4) {
                    Text("时间：")
                        .foregroundColor(.white.opacity(0.8))
                    Text(timeStr)
                        .foregroundColor(useCustomTime ? .yellow : .white)
                        .lineLimit(1)
                    Spacer()
                    Button(action: { showTimePicker = true }) {
                        Image(systemName: useCustomTime ? "clock.badge.checkmark" : "clock")
                            .font(.system(size: 14))
                            .foregroundColor(useCustomTime ? .yellow : .white.opacity(0.7))
                    }
                }
                .font(.system(size: 15, weight: .medium))

                HStack(spacing: 4) {
                    Text("备注：")
                        .foregroundColor(.white.opacity(0.8))
                    if showNoteInput {
                        TextField("输入备注...", text: $noteText)
                            .foregroundColor(.white)
                            .tint(.white)
                            .font(.system(size: 15, weight: .medium))
                            .onSubmit { showNoteInput = false }
                    } else {
                        Text(noteText.isEmpty ? "点击添加" : noteText)
                            .foregroundColor(noteText.isEmpty ? .white.opacity(0.5) : .white)
                            .onTapGesture { showNoteInput = true }
                    }
                }
                .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.55))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .sheet(isPresented: $showTimePicker) {
                timePickerSheet
            }
            .sheet(isPresented: $showCoordPicker) {
                coordPickerSheet
            }
        }
    }

    // MARK: - 时间设置弹窗

    private var timePickerSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Toggle("使用自定义时间", isOn: $useCustomTime)
                    .padding(.horizontal)

                if useCustomTime {
                    DatePicker(
                        "选择时间",
                        selection: $customTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.horizontal)

                    DatePicker(
                        "选择时间",
                        selection: $customTime,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                }

                Button("恢复为当前时间") {
                    useCustomTime = false
                    customTime = Date()
                }
                .foregroundColor(.blue)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("设置水印时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showTimePicker = false }
                }
            }
        }
    }

    // MARK: - 经纬度设置弹窗

    private var coordPickerSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                Toggle("使用自定义经纬度", isOn: $useCustomCoord)
                    .padding(.horizontal)

                if useCustomCoord {
                    // 经度输入
                    VStack(alignment: .leading, spacing: 4) {
                        Text("经度 (Longitude)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("例如: 118.765432", value: $customLongitude, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                            Stepper("", value: $customLongitude, in: -180...180, step: 0.001)
                                .labelsHidden()
                        }
                        .padding(.horizontal)
                    }

                    // 纬度输入
                    VStack(alignment: .leading, spacing: 4) {
                        Text("纬度 (Latitude)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("例如: 33.456789", value: $customLatitude, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                            Stepper("", value: $customLatitude, in: -90...90, step: 0.001)
                                .labelsHidden()
                        }
                        .padding(.horizontal)
                    }

                    // 自定义地址
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自定义地址（可选）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("例如: 泗洪县古徐广场", text: $customAddress)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                    }

                    // 显示当前设置的坐标
                    VStack(alignment: .leading, spacing: 4) {
                        Text("预览")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("经度: \(String(format: "%.6f", customLongitude))")
                            .font(.system(.caption, design: .monospaced))
                        Text("纬度: \(String(format: "%.6f", customLatitude))")
                            .font(.system(.caption, design: .monospaced))
                        if !customAddress.isEmpty {
                            Text("地址: \(customAddress)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)

                    // 使用当前GPS坐标
                    Button("使用当前GPS坐标") {
                        if currentLongitude != "---" {
                            customLongitude = Double(currentLongitude) ?? customLongitude
                        }
                        if currentLatitude != "---" {
                            customLatitude = Double(currentLatitude) ?? customLatitude
                        }
                        customAddress = currentAddress
                    }
                    .foregroundColor(.blue)
                }

                Button("恢复为GPS定位") {
                    useCustomCoord = false
                    customAddress = ""
                }
                .foregroundColor(.red)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("设置经纬度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showCoordPicker = false }
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label)：")
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .font(.system(size: 15, weight: .medium))
    }

    // MARK: - 模式切换栏

    private var modeSwitchBar: some View {
        HStack(spacing: 0) {
            ForEach(CameraMode.allCases, id: \.self) { mode in
                Button(action: {
                    if !camera.isRecording { cameraMode = mode }
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 15, weight: cameraMode == mode ? .bold : .regular))
                        .foregroundColor(cameraMode == mode ? .orange : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .padding(.horizontal, 60)
        .padding(.top, 8)
    }

    // MARK: - 底部控制栏

    private var bottomControlBar: some View {
        HStack {
            // 左：相册
            Button(action: { openPhotoLibrary() }) {
                VStack(spacing: 2) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22))
                    Text("图册")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
            }

            Spacer()

            // 中：快门/录制按钮
            Group {
                if cameraMode == .photo {
                    shutterButton
                } else {
                    recordButton
                }
            }

            Spacer()

            // 右：水印（打开设置）
            Button(action: { showSettings = true }) {
                VStack(spacing: 2) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                    Text("设置")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 60, height: 60)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - 快门按钮

    private var shutterButton: some View {
        Button(action: capturePhoto) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(isCapturing ? Color.gray : Color.white)
                    .frame(width: 60, height: 60)
            }
        }
        .disabled(isCapturing || !camera.isReady)
    }

    // MARK: - 录制按钮

    private var recordButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                if camera.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(camera.isReady ? Color.red : Color.gray)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(!camera.isReady)
    }

    // MARK: - 打开相册

    private func openPhotoLibrary() {
        // 打开系统照片 App
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 拍照

    private func capturePhoto() {
        guard !isCapturing, !isCountingDown, camera.isReady else { return }

        if delaySeconds > 0 {
            startCountdown(delaySeconds) {
                isCapturing = true
                camera.capturePhoto()
            }
        } else {
            isCapturing = true
            camera.capturePhoto()
        }
    }

    // MARK: - 倒计时

    private func startCountdown(_ seconds: Int, onComplete: @escaping () -> Void) {
        isCountingDown = true
        countdownRemaining = seconds

        func tick() {
            if countdownRemaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    countdownRemaining -= 1
                    tick()
                }
            } else {
                isCountingDown = false
                onComplete()
            }
        }
        tick()
    }

    // MARK: - 录像

    private func toggleRecording() {
        if camera.isRecording {
            recordingStartTime = nil
            camera.stopRecording()
        } else {
            recordingStartTime = Date()
            // 同步水印设置
            camera.watermarkFontSizeScale = settings.watermarkFontSize / 24.0
            camera.watermarkVerticalPosition = settings.watermarkVerticalPosition
            camera.startRecording()
        }
    }

    // MARK: - 构建水印文本

    /// 构建水印行数组（与界面信息叠加层一致）
    private func buildWatermarkLines() -> [String] {
        var lines: [String] = []

        // 使用自定义经纬度或GPS定位
        let displayLon = useCustomCoord ? String(format: "%.6f", customLongitude) : currentLongitude
        let displayLat = useCustomCoord ? String(format: "%.6f", customLatitude) : currentLatitude
        let displayAddr: String
        if useCustomCoord && !customAddress.isEmpty {
            displayAddr = customAddress
        } else {
            displayAddr = currentAddress
        }

        lines.append("经度：\(displayLon)")
        lines.append("纬度：\(displayLat)")
        lines.append("坐标：WGS84 坐标系")
        lines.append("地址：\(displayAddr)")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        // 使用自定义时间或当前时间
        let displayTime = useCustomTime ? customTime : Date()
        lines.append("时间：\(f.string(from: displayTime))")
        if !noteText.isEmpty {
            lines.append("备注：\(noteText)")
        }
        return lines
    }

    /// 构建水印文本（多行字符串，用于录像）
    private func buildWatermarkText() -> String {
        return buildWatermarkLines().joined(separator: "\n")
    }

    // MARK: - 拍照完成回调

    private func handleCapturedPhoto(_ image: UIImage?) {
        defer { isCapturing = false }
        guard let image = image else {
            print("[ContentView] 拍照失败")
            return
        }

        // 构建水印行（与界面信息叠加层一致）
        let watermarkLines = buildWatermarkLines()

        // 计算字号缩放倍数（设置值 / 基准值24）
        let fontSizeScale = settings.watermarkFontSize / 24.0

        let watermarkedImage = ImageWatermark.draw(
            on: image,
            lines: watermarkLines,
            fontSizeScale: fontSizeScale,
            verticalPosition: settings.watermarkVerticalPosition
        )

        savePhotoToLibrary(watermarkedImage)

        if settings.autoUpload {
            uploadImage(watermarkedImage)
        }
    }

    // MARK: - 录像完成回调

    private func handleVideoRecorded(_ url: URL?) {
        guard let url = url else {
            print("[ContentView] 录像失败")
            return
        }
        print("[ContentView] 视频已保存: \(url.lastPathComponent)")
        saveVideoToLibrary(url)

        if settings.autoUpload {
            uploadVideo(url)
        }
    }

    // MARK: - 保存相册

    private func savePhotoToLibrary(_ image: UIImage) {
        guard hasPhotoLibraryPermission() else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            print("[ContentView] 照片保存: \(success ? "成功" : "失败")")
        }
    }

    private func saveVideoToLibrary(_ url: URL) {
        guard hasPhotoLibraryPermission() else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            print("[ContentView] 视频保存: \(success ? "成功" : "失败")")
        }
    }

    private func hasPhotoLibraryPermission() -> Bool {
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }
        return status == .authorized || status == .limited
    }

    // MARK: - 上传到百度网盘

    private func uploadImage(_ image: UIImage) {
        BaiduUploader.shared.uploadImage(
            image,
            fileNamePrefix: noteText.isEmpty ? nil : noteText,
            onProgress: { progress in print("[Baidu] 上传: \(Int(progress * 100))%") },
            onSuccess: {
                uploadResultMessage = "已上传到百度网盘"
                showUploadResult = true
            },
            onFailure: { error in
                uploadResultMessage = "上传失败: \(error.localizedDescription)"
                showUploadResult = true
            }
        )
    }

    private func uploadVideo(_ url: URL) {
        BaiduUploader.shared.uploadVideo(
            url,
            fileNamePrefix: noteText.isEmpty ? nil : noteText,
            onProgress: { progress in print("[Baidu] 上传: \(Int(progress * 100))%") },
            onSuccess: {
                uploadResultMessage = "视频已上传到百度网盘"
                showUploadResult = true
            },
            onFailure: { error in
                uploadResultMessage = "上传失败: \(error.localizedDescription)"
                showUploadResult = true
            }
        )
    }

    // MARK: - 定位更新

    private func startLocationUpdates() {
        LocationManager.shared.requestLocation { [self] result in
            handleLocationResult(result)
        }
    }

    private func handleLocationResult(_ result: LocationResult) {
        switch result {
        case .success(let lon, let lat, let address):
            currentLongitude = String(format: "%.6f", lon)
            currentLatitude = String(format: "%.6f", lat)
            currentAddress = address
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                LocationManager.shared.requestLocation { result in
                    handleLocationResult(result)
                }
            }
        case .failure(let error):
            currentLongitude = "---"
            currentLatitude = "---"
            switch error {
            case .permissionDenied, .accuracyReduced:
                currentAddress = "定位权限未开启"
                showLocationPermissionAlert = true
            case .serviceDisabled:
                currentAddress = "定位服务已关闭"
            case .timeout:
                currentAddress = "定位超时"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    LocationManager.shared.requestLocation { result in
                        handleLocationResult(result)
                    }
                }
            case .clError:
                currentAddress = "定位错误"
            }
        }
    }
}
