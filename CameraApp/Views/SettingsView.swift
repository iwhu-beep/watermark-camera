//
//  SettingsView.swift
//  CameraApp
//
//  设置页：百度网盘配置、坐标格式、水印设置
//  路径: CameraApp/Views/SettingsView.swift
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showBaiduAuth: Bool = false
    @State private var baiduLoginStatus: String = ""
    @State private var showWatermarkTool: Bool = false
    @State private var sendResult: String = ""
    @State private var isSending: Bool = false
    @State private var showSMTPConfig: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // ========== 工具 ==========
                Section {
                    Button(action: { showWatermarkTool = true }) {
                        HStack {
                            Image(systemName: "text.badge.plus")
                                .foregroundColor(.blue)
                            Text("水印工具")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("工具")
                } footer: {
                    Text("选择已有图片，添加自定义水印数据")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // ========== 邮箱发送 ==========
                Section {
                    HStack {
                        Text("收件邮箱")
                        Spacer()
                        TextField("example@mail.com", text: $settings.recipientEmail)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("今日照片")
                        Spacer()
                        Text("\(PhotoStore.shared.todayPhotoCount) 张")
                            .foregroundColor(.secondary)
                    }

                    Button(action: { showSMTPConfig = true }) {
                        HStack {
                            Image(systemName: "gearshape")
                            Text("SMTP 服务器配置")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: sendTodayPhotos) {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("发送今日照片")
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(isSending || PhotoStore.shared.todayPhotoCount == 0)

                    if !sendResult.isEmpty {
                        Text(sendResult)
                            .font(.caption)
                            .foregroundColor(sendResult.contains("成功") ? .green : .red)
                    }
                } header: {
                    Text("邮箱发送")
                } footer: {
                    Text("将当天照片按备注名压缩为 ZIP 后通过 SMTP 发送")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // ========== 上传设置 ==========
                Section {
                    Toggle("自动上传到百度网盘", isOn: $settings.autoUpload)

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
                    Text("上传设置")
                } footer: {
                    Text("拍照/录像后自动上传到百度网盘 /apps/拍照/ 目录")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
            .sheet(isPresented: $showWatermarkTool) {
                WatermarkToolView().environmentObject(settings)
            }
            .sheet(isPresented: $showSMTPConfig) {
                SMTPConfigView().environmentObject(settings)
            }
        }
    }

    // MARK: - 发送今日照片

    private func sendTodayPhotos() {
        guard !settings.recipientEmail.isEmpty else {
            sendResult = "请先填写收件邮箱地址"
            return
        }
        guard !settings.smtpUser.isEmpty, !settings.smtpPassword.isEmpty else {
            sendResult = "请先配置 SMTP 服务器"
            return
        }

        isSending = true
        sendResult = "正在压缩照片..."

        DispatchQueue.global(qos: .userInitiated).async {
            let groups = PhotoStore.shared.getTodayGroupedByNote()
            let zips = ZipUtility.createZips(from: groups)

            DispatchQueue.main.async {
                if zips.isEmpty {
                    isSending = false
                    sendResult = "今天没有可发送的照片"
                    return
                }

                let zipURLs = zips.map { $0.1 }
                let zipNames = zips.map { $0.0 }
                sendResult = "已压缩 \(zips.count) 个文件，正在发送..."

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let dateStr = formatter.string(from: Date())
                let subject = "打卡相机照片 - \(dateStr)"
                let body = "附件为当天拍摄的照片，按备注名分组压缩。\n\n压缩包：\n\(zipNames.joined(separator: "\n"))"

                SMTPMailService.sendMail(
                    host: settings.smtpHost,
                    port: settings.smtpPort,
                    user: settings.smtpUser,
                    password: settings.smtpPassword,
                    useTLS: settings.smtpUseTLS,
                    to: settings.recipientEmail,
                    subject: subject,
                    text: body,
                    attachments: zipURLs
                ) { success, message in
                    self.isSending = false
                    self.sendResult = message
                    // 清理临时 ZIP 文件
                    ZipUtility.cleanup(zipURLs: zipURLs)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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
