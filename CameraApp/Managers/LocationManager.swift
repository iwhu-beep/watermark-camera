//
//  LocationManager.swift
//  CameraApp
//
//  单例定位工具类：单次获取WGS84经纬度，封装权限判断与引导
//  路径: CameraApp/Managers/LocationManager.swift
//
//  适配 iOS 14+ 精确位置权限开关
//  无定位权限时主动弹窗引导用户去系统设置开启
//

import CoreLocation
import Foundation
import UIKit

// MARK: - 定位结果

/// 单次定位结果
enum LocationResult {
    /// 定位成功，返回经纬度
    case success(longitude: Double, latitude: Double)
    /// 定位失败
    case failure(error: LocationError)
}

// MARK: - 定位错误枚举

/// 定位失败错误类型
enum LocationError: Error, LocalizedError {
    /// 用户未授予定位权限
    case permissionDenied
    /// 用户授予了模糊位置权限（iOS 14+），未开启精确定位
    case accuracyReduced
    /// 定位服务被系统禁用（设备级开关关闭）
    case serviceDisabled
    /// 定位超时
    case timeout
    /// CoreLocation 返回错误
    case clError(CLError)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未授予定位权限，请在系统设置中开启"
        case .accuracyReduced:
            return "定位精度为模糊位置，请在系统设置中开启精确定位"
        case .serviceDisabled:
            return "设备定位服务已关闭，请在系统设置中开启"
        case .timeout:
            return "定位超时，请检查信号后重试"
        case .clError(let error):
            return "定位失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 单例定位管理器

/// 单例定位工具类
///
/// 用法：
/// ```swift
/// LocationManager.shared.requestLocation { result in
///     switch result {
///     case .success(let lon, let lat):
///         print("经度: \(lon), 纬度: \(lat)")
///     case .failure(let error):
///         print(error.localizedDescription)
///     }
/// }
/// ```
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - 单例

    static let shared = LocationManager()

    // MARK: - 公开属性

    /// 最近一次定位结果（供SwiftUI视图绑定）
    @Published private(set) var lastResult: LocationResult?

    /// 当前是否正在定位
    @Published private(set) var isLocating: Bool = false

    // MARK: - 私有属性

    private let manager = CLLocationManager()

    /// 单次定位回调
    private var locationCompletion: ((LocationResult) -> Void)?

    /// 定位超时计时器
    private var timeoutTimer: Timer?

    /// 超时时间（秒）
    private let timeoutInterval: TimeInterval = 10.0

    // MARK: - 初始化

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - 权限检查

    /// 当前定位权限状态
    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// 是否已获得定位权限（至少WhenInUse）
    var hasLocationPermission: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// 是否已获得精确位置权限（iOS 14+ 检查 accuracyAuthorization）
    var hasPreciseLocation: Bool {
        if #available(iOS 14, *) {
            return manager.accuracyAuthorization == .fullAccuracy
        }
        return true // iOS 14以下无模糊定位概念
    }

    // MARK: - 单次定位请求

    /// 请求单次定位，回调返回经纬度或错误
    ///
    /// 内部自动处理权限检查：
    /// - 未请求过权限 → 先弹系统授权弹窗
    /// - 权限被拒绝 → 回调 `.permissionDenied`，可配合 `showPermissionAlert()` 引导用户
    /// - 精度降级（iOS 14+模糊定位）→ 回调 `.accuracyReduced`
    /// - 权限正常 → 发起单次定位
    ///
    /// - Parameter completion: 定位结果回调（主线程）
    func requestLocation(completion: @escaping (LocationResult) -> Void) {
        // 防止重复请求
        guard !isLocating else { return }

        // 1. 检查定位服务是否开启
        guard CLLocationManager.locationServicesEnabled() else {
            deliverResult(.failure(error: .serviceDisabled), completion: completion)
            return
        }

        // 2. 检查权限状态
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            // 首次请求，弹系统授权弹窗
            locationCompletion = completion
            manager.requestWhenInUseAuthorization()
            return // 等delegate回调后再发起定位

        case .restricted, .denied:
            deliverResult(.failure(error: .permissionDenied), completion: completion)
            return

        case .authorizedWhenInUse, .authorizedAlways:
            break // 权限OK，继续往下

        @unknown default:
            break
        }

        // 3. iOS 14+ 检查精确位置开关
        if #available(iOS 14, *) {
            if manager.accuracyAuthorization == .reducedAccuracy {
                deliverResult(.failure(error: .accuracyReduced), completion: completion)
                return
            }
        }

        // 4. 发起单次定位
        startLocating(completion: completion)
    }

    // MARK: - 权限引导

    /// 弹窗引导用户跳转系统设置开启定位/精确定位权限
    ///
    /// 需在UIViewController上下文中调用，通过UIAlertController实现
    /// - Parameter viewController: 当前显示的UIViewController
    func showPermissionAlert(on viewController: UIViewController?) {
        let status = manager.authorizationStatus
        let message: String

        if status == .denied || status == .restricted {
            message = "应用需要定位权限以记录拍摄位置，请在系统设置中开启定位权限。"
        } else if #available(iOS 14, *), manager.accuracyAuthorization == .reducedAccuracy {
            message = "应用需要精确定位以记录准确坐标，请在系统设置中将定位精度改为"精确位置"。"
        } else {
            return // 权限正常，无需引导
        }

        let alert = UIAlertController(
            title: "需要定位权限",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "稍后", style: .cancel))

        viewController?.present(alert, animated: true)
    }

    /// SwiftUI环境下的权限引导弹窗（返回是否需要引导 + 对应提示文本）
    /// - Returns: (需要引导, 提示文本)
    var permissionAlertInfo: (needed: Bool, message: String) {
        let status = manager.authorizationStatus

        if status == .denied || status == .restricted {
            return (true, "应用需要定位权限以记录拍摄位置，请在系统设置中开启定位权限。")
        }
        if #available(iOS 14, *), manager.accuracyAuthorization == .reducedAccuracy {
            return (true, "应用需要精确定位以记录准确坐标，请在系统设置中将定位精度改为"精确位置"。")
        }
        return (false, "")
    }

    // MARK: - 坐标格式化

    /// 将定位结果格式化为水印用坐标文本
    /// - Parameter format: 坐标格式（十进制度 / 度分秒）
    /// - Returns: 格式化后的坐标字符串
    func formatCoordinate(format: CoordinateFormat) -> String {
        guard case .success(let lon, let lat) = lastResult else {
            return "经度：--- 纬度：---"
        }

        switch format {
        case .decimal:
            let lonStr = String(format: "%.6f°%@", abs(lon), lon >= 0 ? "E" : "W")
            let latStr = String(format: "%.6f°%@", abs(lat), lat >= 0 ? "N" : "S")
            return "经度：\(lonStr) 纬度：\(latStr)"

        case .dms:
            let lonDMS = decimalToDMS(lon, isLongitude: true)
            let latDMS = decimalToDMS(lat, isLongitude: false)
            return "经度：\(lonDMS) 纬度：\(latDMS)"
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // 仅在等待授权结果时处理
        guard let completion = locationCompletion else { return }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // iOS 14+ 首次授权后检查精度
            if #available(iOS 14, *) {
                if manager.accuracyAuthorization == .reducedAccuracy {
                    locationCompletion = nil
                    deliverResult(.failure(error: .accuracyReduced), completion: completion)
                    return
                }
            }
            // 权限OK，发起定位
            locationCompletion = nil
            startLocating(completion: completion)

        case .restricted, .denied:
            locationCompletion = nil
            deliverResult(.failure(error: .permissionDenied), completion: completion)

        case .notDetermined:
            break // 等待用户选择

        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        invalidateTimer()
        manager.stopUpdatingLocation()

        let result: LocationResult = .success(
            longitude: location.coordinate.longitude,
            latitude: location.coordinate.latitude
        )

        DispatchQueue.main.async { [weak self] in
            self?.isLocating = false
            self?.lastResult = result
            self?.locationCompletion?(result)
            self?.locationCompletion = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        invalidateTimer()
        manager.stopUpdatingLocation()

        let clError = error as? CLError
        let result: LocationResult = .failure(error: clError.map { .clError($0) } ?? .timeout)

        DispatchQueue.main.async { [weak self] in
            self?.isLocating = false
            self?.lastResult = result
            self?.locationCompletion?(result)
            self?.locationCompletion = nil
        }
    }

    // MARK: - 私有方法

    /// 发起定位
    private func startLocating(completion: @escaping (LocationResult) -> Void) {
        locationCompletion = completion

        DispatchQueue.main.async { [weak self] in
            self?.isLocating = true
        }

        // iOS 14+ 使用 requestLocation 单次定位
        manager.requestLocation()

        // 启动超时计时器
        timeoutTimer = Timer.scheduledTimer(
            withTimeInterval: timeoutInterval,
            repeats: false
        ) { [weak self] _ in
            guard let self = self else { return }
            self.manager.stopUpdatingLocation()

            let result: LocationResult = .failure(error: .timeout)
            DispatchQueue.main.async {
                self.isLocating = false
                self.lastResult = result
                self.locationCompletion?(result)
                self.locationCompletion = nil
            }
        }
    }

    /// 使超时计时器失效
    private func invalidateTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    /// 在主线程回调结果
    private func deliverResult(_ result: LocationResult, completion: @escaping (LocationResult) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.lastResult = result
            completion(result)
        }
    }

    // MARK: - 度分秒转换

    /// 十进制度 → 度分秒
    private func decimalToDMS(_ decimal: Double, isLongitude: Bool) -> String {
        let absolute = abs(decimal)
        let degrees = Int(absolute)
        let minutes = Int((absolute - Double(degrees)) * 60)
        let seconds = ((absolute - Double(degrees)) * 60 - Double(minutes)) * 60

        let direction: String
        if isLongitude {
            direction = decimal >= 0 ? "E" : "W"
        } else {
            direction = decimal >= 0 ? "N" : "S"
        }

        return String(format: "%d°%d'%.1f\"%@", degrees, minutes, seconds, direction)
    }
}