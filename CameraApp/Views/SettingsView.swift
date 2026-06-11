//
//  SettingsView.swift
//  CameraApp
//
//  附加设置页：自动上传开关、坐标格式切换、水印大小调节
//  路径: CameraApp/Views/SettingsView.swift
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // ========== 云盘上传设置 ==========
                Section {
                    Toggle("自动上传到阿里云盘", isOn: $settings.autoUpload)

                    if settings.autoUpload {
                        TextField("Client ID", text: $settings.aliyunClientId)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14))

                        SecureField("Refresh Token", text: $settings.aliyunRefreshToken)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14))

                        TextField("目标文件夹ID（默认 root）", text: $settings.uploadFolderId)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14))
                    }
                } header: {
                    Text("云盘上传")
                } footer: {
                    Text("在阿里云盘开放平台注册应用获取 Client ID，通过 OAuth2 授权获取 Refresh Token")
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

                    // 格式预览
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

                        Slider(
                            value: $settings.watermarkFontSize,
                            in: 10...48,
                            step: 2
                        ) {
                            Text("水印大小")
                        } minimumValueLabel: {
                            Text("小")
                                .font(.caption2)
                        } maximumValueLabel: {
                            Text("大")
                                .font(.caption2)
                        }
                    }

                    // 水印预览
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

    // MARK: - 坐标格式预览文本

    private var previewCoordinateText: String {
        switch settings.coordinateFormat {
        case .decimal:
            return "116.407400°E 39.904200°N"
        case .dms:
            return "116°24'26.6\"E 39°54'15.1\"N"
        }
    }

    // MARK: - 水印预览

    private var watermarkPreview: some View {
        ZStack(alignment: .bottomLeading) {
            // 模拟照片背景
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 80)
                .overlay(
                    Text("模拟照片区域")
                        .foregroundColor(.white.opacity(0.3))
                )

            // 模拟水印
            VStack(alignment: .leading, spacing: 2) {
                Text("经度：116.407400°E 纬度：39.904200°N")
                    .font(.system(size: min(settings.watermarkFontSize * 0.5, 14), weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1, x: 0, y: 0)

                Text("示例备注内容")
                    .font(.system(size: min(settings.watermarkFontSize * 0.5, 14), weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1, x: 0, y: 0)
            }
            .padding(8)
        }
        .cornerRadius(6)
    }
}
