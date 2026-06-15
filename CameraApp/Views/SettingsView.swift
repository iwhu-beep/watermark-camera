//
//  SettingsView.swift
//  CameraApp
//
//  设置页：上传配置、坐标格式、水印设置
//  路径: CameraApp/Views/SettingsView.swift
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var ftpTestResult: String?
    @State private var isTestingFTP: Bool = false
    @State private var showBaiduAuth: Bool = false
    @State private var baiduLoginStatus: String = ""

    var body: some View {
        NavigationView {
            Form {
                // ========== 上传目标 ==========
                Section {
                    Picker("上传目标", selection: $settings.uploadTarget) {
                        ForEach(UploadTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("自动上传", isOn: $settings.autoUpload)
                } header: {
                    Text("上传设置")
                } footer: {
                    Text("拍照/录像后自动上传到选定的目标")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // ========== FTP 配置 ==========
                if settings.uploadTarget == .ftp {
                    Section {
                        TextField("服务器地址 (如 ftp.example.com)", text: $settings.ftpHost)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14))

                        TextField("端口 (默认21)", text: $settings.ftpPort)
                            .keyboardType(.numberPad)
                            .font(.system(size: 14))

                        TextField("用户名", text: $settings.ftpUsername)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14))

                        SecureField("密码", text: $settings.ftpPassword)
                            .font(.system(size: 14))

                        TextField("远程目录 (如 /photos/)", text: $settings.ftpRemoteDir)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14))

                        Button(action: testFTPConnection) {
                            HStack {
                                if isTestingFTP {
                                    ProgressView().scaleEffect(0.8)
                                }
                                Text(isTestingFTP ? "测试中..." : "测试连接")
                                    .foregroundColor(.blue)
                            }
                        }
                        .disabled(isTestingFTP || settings.ftpHost.isEmpty)

                        if let result = ftpTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("成功") ? .green : .red)
                        }
                    } header: {
                        Text("FTP 配置")
                    }
                }

                // ========== 百度网盘配置 ==========
                if settings.uploadTarget == .baidu {
                    Section {
                        if BaiduUploader.shared.isLoggedIn() {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("已登录百度网盘")
                                    .foregroundColor(.green)
                            }

                            Button(action: {
                                BaiduUploader.shared.logout()
                                baiduLoginStatus = "已退出登录"
                            }) {
                                Text("退出登录")
                                    .foregroundColor(.red)
                            }
                        } else {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("未登录")
                                    .foregroundColor(.secondary)
                            }

                            Button(action: { showBaiduAuth = true }) {
                                HStack {
                                    Image(systemName: "person.circle")
                                    Text("登录百度网盘")
                                }
                                .foregroundColor(.blue)
                            }
                        }

                        if !baiduLoginStatus.isEmpty {
                            Text(baiduLoginStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("百度网盘")
                    } footer: {
                        Text("文件将上传到网盘的 /apps/拍照/ 目录")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // ========== 坐标格式 ==========
                Section {
                    Picker("坐标格式", selection: $settings.coordinateFormat) {
                        ForEach(CoordinateFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("预览")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(previewCoordinateText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("坐标格式")
                }

                // ========== 水印设置 ==========
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("水印大小")
                            Spacer()
                            Text("\(Int(settings.watermarkFontSize))")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $settings.watermarkFontSize, in: 12...120, step: 2) {
                            Text("水印大小")
                        } minimumValueLabel: {
                            Text("小").font(.caption2)
                        } maximumValueLabel: {
                            Text("大").font(.caption2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("垂直位置")
                            Spacer()
                            Text(positionLabel)
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $settings.watermarkVerticalPosition, in: 0...1, step: 0.05) {
                            Text("垂直位置")
                        } minimumValueLabel: {
                            Text("底部").font(.caption2)
                        } maximumValueLabel: {
                            Text("顶部").font(.caption2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("预览效果")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        watermarkPreview
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("水印设置")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showBaiduAuth) {
                BaiduAuthView { success, message in
                    baiduLoginStatus = message
                }
            }
        }
    }

    // MARK: - 位置标签

    private var positionLabel: String {
        let pos = settings.watermarkVerticalPosition
        if pos < 0.2 { return "底部" }
        else if pos < 0.4 { return "偏下" }
        else if pos < 0.6 { return "居中" }
        else if pos < 0.8 { return "偏上" }
        else { return "顶部" }
    }

    // MARK: - 测试 FTP 连接

    private func testFTPConnection() {
        isTestingFTP = true
        ftpTestResult = nil

        FTPConfig.host = settings.ftpHost
        FTPConfig.port = Int(settings.ftpPort) ?? 21
        FTPConfig.username = settings.ftpUsername
        FTPConfig.password = settings.ftpPassword
        FTPConfig.remoteDir = settings.ftpRemoteDir

        FTPUploader.shared.testConnection { success, msg in
            isTestingFTP = false
            if success {
                ftpTestResult = "✓ \(msg)"
            } else {
                ftpTestResult = "✗ \(msg)"
            }
        }
    }

    // MARK: - 坐标格式预览

    private var previewCoordinateText: String {
        switch settings.coordinateFormat {
        case .decimal:
            return "116.407400\u{00b0}E 39.904200\u{00b0}N"
        case .dms:
            return "116\u{00b0}24'26.6\"E 39\u{00b0}54'15.1\"N"
        }
    }

    // MARK: - 水印预览

    private var watermarkPreview: some View {
        GeometryReader { geo in
            let previewFontSize = min(settings.watermarkFontSize * 0.4, 16)
            let position = settings.watermarkVerticalPosition

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 100)
                    .overlay(Text("模拟照片区域").foregroundColor(.white.opacity(0.3)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("备注内容")
                        .font(.system(size: previewFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 1)
                    Text("2026年06月11日 14:30:25")
                        .font(.system(size: previewFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 1)
                    Text("经度:116.407400\u{00b0}E 纬度:39.904200\u{00b0}N")
                        .font(.system(size: previewFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 1)
                }
                .padding(8)
                .offset(y: CGFloat(position) * max(0, 100 - 80))
            }
        }
        .frame(height: 100)
        .cornerRadius(6)
    }
}
