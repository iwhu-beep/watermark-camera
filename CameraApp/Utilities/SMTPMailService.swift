//
//  SMTPMailService.swift
//  CameraApp
//
//  SMTP 邮件发送服务：使用 Swift-SMTP 直接发送邮件
//  路径: CameraApp/Utilities/SMTPMailService.swift
//

import Foundation
import SwiftSMTP

/// SMTP 邮件发送服务
final class SMTPMailService {

    /// 发送带附件的邮件
    /// - Parameters:
    ///   - host: SMTP 服务器地址
    ///   - port: 端口号
    ///   - user: 登录用户名（邮箱地址）
    ///   - password: 密码/授权码
    ///   - useTLS: 是否使用 TLS
    ///   - to: 收件人邮箱
    ///   - subject: 邮件主题
    ///   - text: 邮件正文
    ///   - attachments: 附件文件 URL 数组
    ///   - completion: 完成回调
    static func sendMail(
        host: String,
        port: Int,
        user: String,
        password: String,
        useTLS: Bool,
        to: String,
        subject: String,
        text: String,
        attachments: [URL],
        completion: @escaping (Bool, String) -> Void
    ) {
        // 根据端口选择 TLS 模式
        // 465 → 隐式 TLS (SMTPS)
        // 587/25 → STARTTLS 升级
        let tlsMode: SMTP.TLSMode
        if !useTLS {
            tlsMode = .ignoreTLS
        } else if port == 465 {
            tlsMode = .requireTLS       // 隐式 TLS
        } else {
            tlsMode = .requireSTARTTLS  // STARTTLS 升级
        }

        // 配置 SMTP 服务器
        let smtp = SMTP(
            hostname: host,
            email: user,
            password: password,
            port: Int32(port),
            tlsMode: tlsMode,
            tlsConfiguration: nil,
            authMethods: [],
            domainName: "打卡相机",
            timeout: 30
        )

        // 构建附件
        var mailAttachments: [Attachment] = []
        for url in attachments {
            let attachment = Attachment(filePath: url.path)
            mailAttachments.append(attachment)
        }

        // 构建邮件
        let mail = Mail(
            from: Mail.User(name: "打卡相机", email: user),
            to: [Mail.User(name: "", email: to)],
            subject: subject,
            text: text,
            attachments: mailAttachments
        )

        // 发送
        smtp.send(mail) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[SMTP] 发送失败: \(error.localizedDescription)")
                    completion(false, "发送失败: \(error.localizedDescription)")
                } else {
                    print("[SMTP] 发送成功")
                    completion(true, "发送成功")
                }
            }
        }
    }
}
