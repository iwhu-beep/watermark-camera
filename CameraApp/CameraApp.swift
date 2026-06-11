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
    
    init() {
        // 设置崩溃日志
        setupCrashReporting()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(permissionManager)
        }
    }
    
    private func setupCrashReporting() {
        // 捕获未处理的异常
        NSSetUncaughtExceptionHandler { exception in
            print("=== CRASH ===")
            print("Name: \(exception.name.rawValue)")
            print("Reason: \(exception.reason ?? "unknown")")
            print("Stack: \(exception.callStackSymbols.joined(separator: "\n"))")
            
            // 写入文件
            let log = """
            === CRASH ===
            Time: \(Date())
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            if let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("crash.log") {
                try? log.write(to: path, atomically: true, encoding: .utf8)
                print("Crash log saved to: \(path)")
            }
        }
        
        // 捕获信号
        signal(SIGABRT) { _ in
            print("=== SIGABRT ===")
        }
        signal(SIGSEGV) { _ in
            print("=== SIGSEGV ===")
        }
    }
}
