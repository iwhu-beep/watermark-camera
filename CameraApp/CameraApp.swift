//
//  CameraApp.swift
//  CameraApp
//
//  水印相机 - 带定位水印的拍照应用
//  适配 iOS 15+
//

import SwiftUI

@main
struct CameraApp: App {
    /// 全局设置
    @StateObject private var settings = AppSettings()
    /// 权限管理器
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(permissionManager)
        }
    }
}
