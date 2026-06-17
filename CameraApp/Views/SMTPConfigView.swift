//
//  SMTPConfigView.swift
//  CameraApp
//
//  SMTP 服务器配置页面
//  路径: CameraApp/Views/SMTPConfigView.swift
//

import SwiftUI

struct SMTPConfigView: View {

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // ========== SMTP 服务器 ==========
                Section {
                    HStack {
                        Text("服务器地址")
                        Spacer()
                        TextField("smtp.qq.com", text: $settings.smtpHost)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("端口")
                        Spacer()
                        TextField("465", value: $settings.smtpPort, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .foregroundColor(.secondary)
                            .frame(width: 80)
                    }

                    Toggle("使用 TLS 加密", isOn: $settings.smtpUseTLS)
                } header: {
                    Text("SMTP 服务器")
                } footer: {
                    Text("常用端口：QQ邮箱 465/587，163邮箱 465，Gmail 587")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // ========== 账号信息 ==========
                Section {
                    HStack {
                        Text("发件邮箱")
                        Spacer()
                        TextField("your@qq.com", text: $settings.smtpUser)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("授权码/密码")
                        Spacer()
                        SecureField("输入授权码", text: $settings.smtpPassword)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("账号信息")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("QQ邮箱：设置 → 账户 → 开启 SMTP → 获取授权码")
                        Text("163邮箱：设置 → POP3/SMTP → 开启 → 获取授权码")
                        Text("Gmail：使用应用专用密码")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                // ========== 常用配置 ==========
                Section {
                    Button("QQ邮箱 (smtp.qq.com:465)") {
                        settings.smtpHost = "smtp.qq.com"
                        settings.smtpPort = 465
                        settings.smtpUseTLS = true
                    }
                    .foregroundColor(.blue)

                    Button("163邮箱 (smtp.163.com:465)") {
                        settings.smtpHost = "smtp.163.com"
                        settings.smtpPort = 465
                        settings.smtpUseTLS = true
                    }
                    .foregroundColor(.blue)

                    Button("Gmail (smtp.gmail.com:587)") {
                        settings.smtpHost = "smtp.gmail.com"
                        settings.smtpPort = 587
                        settings.smtpUseTLS = true
                    }
                    .foregroundColor(.blue)

                    Button("Outlook (smtp.office365.com:587)") {
                        settings.smtpHost = "smtp.office365.com"
                        settings.smtpPort = 587
                        settings.smtpUseTLS = true
                    }
                    .foregroundColor(.blue)
                } header: {
                    Text("快速配置")
                }
            }
            .navigationTitle("SMTP 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
