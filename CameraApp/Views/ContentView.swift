//
//  ContentView.swift
//  CameraApp
//
//  主界面：全屏取景 + 实时信息叠加 + 底部控制栏
//  路径: CameraApp/Views/ContentView.swift
//

import Photos
import SwiftUI

struct ContentView: View {

    // MARK: - 环境依赖

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissionManager: PermissionManager

    // MARK: - 状态对象

    @StateObject private var cameraController = CameraController()

    // MARK: - UI状态

    /// 备注输入文本
    @State private var noteText: String = ""
    /// 是否正在拍照（防重复点击）
    @State private var isCapturing: Bool = false
    /// 是否显示上传结果弹窗
    @State private var showUploadResult: Bool = false
    /// 上传结果消息
    @State private var uploadResultMessage: String = ""
    /// 是否显示设置页
    @State private var showSettings: Bool = false
    /// 是否显示定位权限引导弹窗
    @State private var showLocationPermissionAlert: Bool = false
    /// 当前时间（每秒更新）
    @State private var currentTime: String = ""
    /// 当前经度
    @State private var currentLongitude: String = "---"
    /// 当前纬度
    @State private var currentLatitude: String = "---"
    /// 坐标系
    @State private var coordinateSystem: String = "WGS84 坐标系"
    /// 地址
    @State private var currentAddress: String = "定位中..."
    /// 是否正在显示备注输入
    @State private var showNoteInput: Bool = false
    /// 定时器
    @State private var timer: Timer? = nil

    // MARK: - 视图主体

    var body: some View {
        ZStack {
            // ========== 全屏相机预览 ==========
            CameraPreviewView(session: cameraController.session)
                .ignoresSafeArea()

            // ========== 信息叠加层 ==========
            VStack {
                // 顶部工具栏
                topToolBar

                Spacer()

                // 信息叠加区（底部偏上）
                infoOverlay

                // 底部控制栏
                bottomControlBar
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            // 延迟启动，确保 UI 完全加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                permissionManager.requestPermissions()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                cameraController.setupCamera()
                cameraController.onPhotoCaptured = handleCapturedPhoto
            }
            // 启动定位
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                startLocationUpdates()
            }
            // 启动时钟
            updateTime()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                updateTime()
            }
        }
        .onDisappear {
            cameraController.stopCamera()
            timer?.invalidate()
            timer = nil
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
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
        HStack(spacing: 0) {
            // 设置/菜单
            Button(action: { showSettings = true }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // 闪光灯
            Button(action: {}) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            // 切换摄像头
            Button(action: {}) {
                Image(systemName: "camera.rotate.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            // 更多
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - 信息叠加层

    private var infoOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 经度
            HStack(spacing: 4) {
                Text("经度：")
                    .foregroundColor(.white.opacity(0.8))
                Text(currentLongitude)
                    .foregroundColor(.white)
            }
            .font(.system(size: 14, weight: .medium))

            // 纬度
            HStack(spacing: 4) {
                Text("纬度：")
                    .foregroundColor(.white.opacity(0.8))
                Text(currentLatitude)
                    .foregroundColor(.white)
            }
            .font(.system(size: 14, weight: .medium))

            // 坐标系
            HStack(spacing: 4) {
                Text("坐标：")
                    .foregroundColor(.white.opacity(0.8))
                Text(coordinateSystem)
                    .foregroundColor(.white)
            }
            .font(.system(size: 14, weight: .medium))

            // 地址
            HStack(spacing: 4) {
                Text("地址：")
                    .foregroundColor(.white.opacity(0.8))
                Text(currentAddress)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .font(.system(size: 14, weight: .medium))

            // 时间
            HStack(spacing: 4) {
                Text("时间：")
                    .foregroundColor(.white.opacity(0.8))
                Text(currentTime)
                    .foregroundColor(.white)
            }
            .font(.system(size: 14, weight: .medium))

            // 备注
            HStack(spacing: 4) {
                Text("备注：")
                    .foregroundColor(.white.opacity(0.8))
                if showNoteInput {
                    TextField("输入备注...", text: $noteText)
                        .foregroundColor(.white)
                        .tint(.white)
                        .font(.system(size: 14, weight: .medium))
                } else {
                    Text(noteText.isEmpty ? "点击添加" : noteText)
                        .foregroundColor(noteText.isEmpty ? .white.opacity(0.5) : .white)
                        .lineLimit(1)
                        .onTapGesture {
                            showNoteInput = true
                        }
                }
            }
            .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.55))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - 底部控制栏

    private var bottomControlBar: some View {
        HStack {
            // 左：相册
            Button(action: {}) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                    Text("图册")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 60, height: 60)
            }

            Spacer()

            // 中：快门按钮
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
            .disabled(isCapturing)

            Spacer()

            // 右：水印
            Button(action: {}) {
                VStack(spacing: 4) {
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
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - 时间更新

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        currentTime = formatter.string(from: Date())
    }

    // MARK: - 定位更新

    private func startLocationUpdates() {
        // 请求首次定位
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
                currentAddress = "定位超时，重试中..."
                // 超时后重试
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    LocationManager.shared.requestLocation { result in
                        handleLocationResult(result)
                    }
                }
            case .clError:
                currentAddress = "定位错误"
            }
        }
    }

    // MARK: - 拍照流程

    private func capturePhoto() {
        guard !isCapturing else { return }

        // 检查相机是否已就绪
        guard cameraController.isReady else {
            print("[ContentView] 相机未就绪，无法拍照")
            return
        }

        isCapturing = true

        // 直接拍照（定位已在后台持续更新）
        cameraController.capturePhoto()
    }

    /// 拍照完成回调（已在主线程）
    private func handleCapturedPhoto(_ image: UIImage?) {
        defer { isCapturing = false }

        guard let image = image else {
            print("[ContentView] 拍照失败，图像为nil")
            return
        }

        // 1. 生成坐标文本
        let coordinateText: String
        if case .success = LocationManager.shared.lastResult {
            coordinateText = LocationManager.shared.formatCoordinate(format: settings.coordinateFormat)
        } else {
            coordinateText = "经度：\(currentLongitude) 纬度：\(currentLatitude)"
        }

        // 2. 绘制水印
        let watermarkedImage = ImageWatermark.draw(
            on: image,
            coordinate: coordinateText,
            note: noteText.isEmpty ? nil : noteText
        )

        // 3. 保存到相册
        saveToPhotoLibrary(watermarkedImage)

        // 4. 自动上传（如果开启且已配置凭据）
        if settings.autoUpload
            && !settings.aliyunClientId.isEmpty
            && !settings.aliyunRefreshToken.isEmpty {
            uploadToCloud(watermarkedImage)
        }
    }

    // MARK: - 保存相册

    private func saveToPhotoLibrary(_ image: UIImage) {
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }

        guard status == .authorized || status == .limited else {
            print("[ContentView] 相册权限未授予，无法保存")
            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            if success {
                print("[ContentView] 照片已保存到相册")
            } else {
                print("[ContentView] 保存相册失败: \(error?.localizedDescription ?? "未知错误")")
            }
        }
    }

    // MARK: - 云盘上传

    private func uploadToCloud(_ image: UIImage) {
        AliyunDriveConfig.clientId = settings.aliyunClientId
        AliyunDriveConfig.refreshToken = settings.aliyunRefreshToken
        AliyunDriveConfig.uploadFolderId = settings.uploadFolderId

        CloudUploader.shared.uploadImage(
            image,
            folderId: settings.uploadFolderId,
            onProgress: { fraction in
                print("[上传进度] \(Int(fraction * 100))%")
            },
            onSuccess: { downloadUrl in
                uploadResultMessage = "上传成功！\n\(downloadUrl)"
                showUploadResult = true
            },
            onFailure: { error in
                uploadResultMessage = "上传失败: \(error.localizedDescription)"
                showUploadResult = true
            }
        )
    }
}
