//
//  PermissionManager.swift
//  CameraApp
//
//  权限管理器：依次申请相机、定位、相册权限
//  路径: CameraApp/Managers/PermissionManager.swift
//

import AVFoundation
import Photos
import SwiftUI

/// 权限管理器：启动时依次请求相机、精确定位、相册读写权限
class PermissionManager: ObservableObject {

    // MARK: 权限状态

    /// 相机权限是否已授予
    @Published var cameraAuthorized: Bool = false
    /// 定位权限是否已授予（从LocationManager单例读取）
    var locationAuthorized: Bool {
        LocationManager.shared.hasLocationPermission
    }
    /// 相册权限是否已授予
    @Published var photoLibraryAuthorized: Bool = false
    /// 所有权限是否已确定（不管是否授权）
    @Published var allPermissionsDetermined: Bool = false

    /// 定位管理器实例，用于请求权限（由LocationManager接管）
    // LocationManager.shared 负责定位权限

    // MARK: - 依次请求权限

    /// 依次申请：相机 → 精确定位 → 相册读写
    /// 网络权限由系统在首次网络请求时自动弹出，无需手动申请
    func requestPermissions() {
        requestCameraPermission { [weak self] in
            self?.requestLocationPermission {
                self?.requestPhotoLibraryPermission {
                    DispatchQueue.main.async {
                        self?.allPermissionsDetermined = true
                    }
                }
            }
        }
    }

    // MARK: - 相机权限

    private func requestCameraPermission(completion: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            DispatchQueue.main.async { self.cameraAuthorized = true }
            completion()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraAuthorized = granted
                }
                completion()
            }
        default:
            // .denied / .restricted
            completion()
        }
    }

    // MARK: - 定位权限

    private func requestLocationPermission(completion: @escaping () -> Void) {
        // 定位权限已由 LocationManager.shared 接管，此处仅标记状态
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        completion()
    }

    // MARK: - 相册权限

    private func requestPhotoLibraryPermission(completion: @escaping () -> Void) {
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }

        switch status {
        case .authorized, .limited:
            DispatchQueue.main.async { self.photoLibraryAuthorized = true }
            completion()
        case .notDetermined:
            if #available(iOS 14, *) {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] granted in
                    DispatchQueue.main.async {
                        self?.photoLibraryAuthorized = (granted == .authorized || granted == .limited)
                    }
                    completion()
                }
            } else {
                PHPhotoLibrary.requestAuthorization { [weak self] granted in
                    DispatchQueue.main.async {
                        self?.photoLibraryAuthorized = (granted == .authorized || granted == .limited)
                    }
                    completion()
                }
            }
        default:
            // .denied / .restricted
            completion()
        }
    }
}
