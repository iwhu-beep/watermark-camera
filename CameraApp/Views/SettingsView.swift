//
//  SettingsView.swift
//  CameraApp
//
//  设置页：FTP上传配置、坐标格式、水印设置
//  路径: CameraApp/Views/SettingsView.swift
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // ========== FTP 上传设置 ==========
                Section {
                    Toggle("自动上传到 FTP", isOn: $settings.autoUpload)

                    if settings.autoUpload {
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
                    }
                } header: {
                    Text("FTP 上传")
                } footer: {
                    Text("配置 FTP 服务器信息，拍照/录像后自动上传文件")
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

                        Slider(value: $settings.watermarkFontSize, in: 10...48, step: 2) {
                            Text("水印大小")
                        } minimumValueLabel: {
                            Text("小").font(.caption2)
                        } maximumValueLabel: {
                            Text("大").font(.caption2)
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
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 80)
                .overlay(Text("模拟照片区域").foregroundColor(.white.opacity(0.3)))

            VStack(alignment: .leading, spacing: 2) {
                Text("经度:116.407400\u{00b0}E 纬度:39.904200\u{00b0}N")
                    .font(.system(size: min(settings.watermarkFontSize * 0.5, 14), weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1)
                Text("示例备注内容")
                    .font(.system(size: min(settings.watermarkFontSize * 0.5, 14), weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1)
            }
            .padding(8)
        }
        .cornerRadius(6)
    }
}
