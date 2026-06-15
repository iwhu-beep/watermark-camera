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
                Spacer()
                infoOverlay
                modeSwitchBar
                bottomControlBar
            }
        }
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
                // 设置动态水印提供者
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

    // MARK: - 顶部工具栏

    private var topToolBar: some View {
        HStack {
            Button(action: { showSettings = true }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button(action: {}) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            Button(action: {}) {
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

    // MARK: - 实时时间（使用TimelineView避免Timer导致全局刷新）

    private func currentTimeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: - 信息叠加层

    private var infoOverlay: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let timeStr = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return f.string(from: context.date)
            }()

            VStack(alignment: .leading, spacing: 6) {
                infoRow(label: "经度", value: currentLongitude)
                infoRow(label: "纬度", value: currentLatitude)
                infoRow(label: "坐标", value: "WGS84 坐标系")
                infoRow(label: "地址", value: currentAddress)
                infoRow(label: "时间", value: timeStr)
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
            Button(action: {}) {
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

            // 右：水印
            Button(action: {}) {
                VStack(spacing: 2) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                    Text("水印")
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
                    // 停止：方块
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red)
                        .frame(width: 28, height: 28)
                } else {
                    // 开始：红点
                    Circle()
                        .fill(camera.isReady ? Color.red : Color.gray)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(!camera.isReady)
    }

    // MARK: - 拍照

    private func capturePhoto() {
        guard !isCapturing, camera.isReady else { return }
        isCapturing = true
        camera.capturePhoto()
    }

    // MARK: - 录像

    private func toggleRecording() {
        if camera.isRecording {
            camera.stopRecording()
        } else {
            camera.startRecording()
        }
    }

    // MARK: - 构建水印文本

    private func buildWatermarkText() -> String {
        var lines: [String] = []
        lines.append("经度: \(currentLongitude)")
        lines.append("纬度: \(currentLatitude)")
        lines.append("坐标: WGS84 坐标系")
        lines.append("地址: \(currentAddress)")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("时间: \(f.string(from: Date()))")
        if !noteText.isEmpty {
            lines.append("备注: \(noteText)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 拍照完成回调

    private func handleCapturedPhoto(_ image: UIImage?) {
        defer { isCapturing = false }
        guard let image = image else {
            print("[ContentView] 拍照失败")
            return
        }

        // 生成坐标文本
        let coordinateText: String
        if case .success = LocationManager.shared.lastResult {
            coordinateText = LocationManager.shared.formatCoordinate(format: settings.coordinateFormat)
        } else {
            coordinateText = "经度:\(currentLongitude) 纬度:\(currentLatitude)"
        }

        // 绘制水印
        let watermarkedImage = ImageWatermark.draw(
            on: image,
            coordinate: coordinateText,
            note: noteText.isEmpty ? nil : noteText
        )

        // 保存到相册
        savePhotoToLibrary(watermarkedImage)

        // FTP 上传
        if settings.autoUpload && !settings.ftpHost.isEmpty {
            ftpUploadImage(watermarkedImage)
        }
    }

    // MARK: - 录像完成回调

    private func handleVideoRecorded(_ url: URL?) {
        guard let url = url else {
            print("[ContentView] 录像失败")
            return
        }
        print("[ContentView] 视频已保存: \(url.lastPathComponent)")

        // 保存到相册
        saveVideoToLibrary(url)

        // FTP 上传
        if settings.autoUpload && !settings.ftpHost.isEmpty {
            ftpUploadVideo(url)
        }
    }

    // MARK: - 保存相册

    private func savePhotoToLibrary(_ image: UIImage) {
        guard hasPhotoLibraryPermission() else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            print("[ContentView] 照片保存: \(success ? "成功" : "失败 - \(error?.localizedDescription ?? "")")")
        }
    }

    private func saveVideoToLibrary(_ url: URL) {
        guard hasPhotoLibraryPermission() else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            print("[ContentView] 视频保存: \(success ? "成功" : "失败 - \(error?.localizedDescription ?? "")")")
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

    // MARK: - FTP 上传

    private func ftpUploadImage(_ image: UIImage) {
        syncFTPConfig()
        FTPUploader.shared.uploadImage(
            image,
            onProgress: { progress in print("[FTP] 上传: \(Int(progress * 100))%") },
            onSuccess: {
                uploadResultMessage = "上传成功"
                showUploadResult = true
            },
            onFailure: { error in
                uploadResultMessage = "上传失败: \(error.localizedDescription)"
                showUploadResult = true
            }
        )
    }

    private func ftpUploadVideo(_ url: URL) {
        syncFTPConfig()
        FTPUploader.shared.uploadVideo(
            url,
            onProgress: { progress in print("[FTP] 上传: \(Int(progress * 100))%") },
            onSuccess: {
                uploadResultMessage = "视频上传成功"
                showUploadResult = true
            },
            onFailure: { error in
                uploadResultMessage = "上传失败: \(error.localizedDescription)"
                showUploadResult = true
            }
        )
    }

    /// 同步设置到 FTP 配置
    private func syncFTPConfig() {
        FTPConfig.host = settings.ftpHost
        FTPConfig.port = Int(settings.ftpPort) ?? 21
        FTPConfig.username = settings.ftpUsername
        FTPConfig.password = settings.ftpPassword
        FTPConfig.remoteDir = settings.ftpRemoteDir
    }

    // MARK: - 定位更新

    private func startLocationUpdates() {
        LocationManager.shared.requestLocation { [self] result in
            handleLocationResult(result)
        }
    }

    private func handleLocationResult(_ result: LocationResult) {
        switch result {
        case .success(let lon, let lat):
            currentLongitude = String(format: "%.6f", lon)
            currentLatitude = String(format: "%.6f", lat)
            currentAddress = "GPS定位"
            // 成功后继续请求（保持更新）
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
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
