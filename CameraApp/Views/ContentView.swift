//
//  ContentView.swift
//  CameraApp
//
//  主界面：相机取景 + 备注输入 + 快门按钮 + 保存/上传流程
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

    // MARK: - 视图主体

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 全屏黑色背景
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ========== 相机取景器 ==========
                    CameraPreviewView(session: cameraController.session)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.width * 4.0 / 3.0
                        )
                        .clipped()

                    Spacer()

                    // ========== 底部控制区 ==========
                    controlBar
                }
            }
            .navigationBarHidden(true)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            // 延迟启动，确保 UI 完全加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                permissionManager.requestPermissions()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                cameraController.setupCamera()
                cameraController.onPhotoCaptured = handleCapturedPhoto
            }
        }
        .onDisappear {
            cameraController.stopCamera()
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

    // MARK: - 底部控制栏

    private var controlBar: some View {
        VStack(spacing: 16) {

            // ========== 备注输入框 ==========
            HStack(spacing: 8) {
                TextField("输入备注内容...", text: $noteText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .tint(.white)
                    .font(.system(size: 15))

                // 清除按钮
                if !noteText.isEmpty {
                    Button(action: { noteText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 18))
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)

            // ========== 快门 + 设置 ==========
            HStack {
                // 左：设置按钮
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
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

                // 右：定位状态指示
                LocationStatusBadge()
                    .frame(width: 50, height: 50)
            }
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.75))
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

        // 先请求单次定位，拿到结果后再拍照
        LocationManager.shared.requestLocation { [self] result in
            print("[ContentView] 定位完成: \(result)")
            // 定位完成后触发拍照
            cameraController.capturePhoto()
        }
    }

    /// 拍照完成回调（已在主线程）
    private func handleCapturedPhoto(_ image: UIImage?) {
        defer { isCapturing = false }
        
        guard let image = image else {
            print("[ContentView] 拍照失败，图像为nil")
            return
        }
        
        // 1. 读取定位结果，生成坐标文本
        let coordinateText: String
        if case .success = LocationManager.shared.lastResult {
            coordinateText = LocationManager.shared.formatCoordinate(format: settings.coordinateFormat)
            print("[ContentView] 坐标: \(coordinateText)")
        } else if case .failure(let error) = LocationManager.shared.lastResult {
            coordinateText = "经度：--- 纬度：---"
            print("[ContentView] 定位失败: \(error)")
            // 无权限或精度降级时弹窗引导用户去设置
            switch error {
            case .permissionDenied, .accuracyReduced:
                showLocationPermissionAlert = true
            default:
                break
            }
        } else {
            coordinateText = "经度：--- 纬度：---"
            print("[ContentView] 无定位结果")
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
        // 同步配置到 AliyunDriveConfig
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

// MARK: - 定位状态指示器

/// 显示当前定位状态的小图标（从单例读取）
struct LocationStatusBadge: View {
    @ObservedObject private var locationManager = LocationManager.shared

    var body: some View {
        VStack(spacing: 2) {
            let isLocated: Bool = {
                if case .success = locationManager.lastResult { return true }
                return false
            }()
            Image(systemName: isLocated ? "location.fill" : "location.slash")
                .font(.system(size: 18))
                .foregroundColor(isLocated ? .green : .red.opacity(0.7))
        }
    }
}
