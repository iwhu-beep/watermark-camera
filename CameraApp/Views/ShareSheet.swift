//
//  ShareSheet.swift
//  CameraApp
//
//  系统分享面板封装（支持微信、QQ、AirDrop 等）
//  路径: CameraApp/Views/ShareSheet.swift
//

import SwiftUI
import UIKit

/// 系统分享面板（UIActivityViewController 封装）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
