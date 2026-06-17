//
//  MailView.swift
//  CameraApp
//
//  邮件发送视图：封装 MFMailComposeViewController
//  路径: CameraApp/Views/MailView.swift
//

import SwiftUI
import MessageUI

/// 邮件发送视图包装器
struct MailView: UIViewControllerRepresentable {

    let recipients: [String]
    let subject: String
    let body: String
    let attachments: [(data: Data, mimeType: String, fileName: String)]

    @Environment(\.dismiss) private var dismiss
    var onResult: ((Result<Void, Error>) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)

        for attachment in attachments {
            vc.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailView

        init(_ parent: MailView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error = error {
                parent.onResult?(.failure(error))
            } else if result == .sent {
                parent.onResult?(.success(()))
            } else {
                parent.onResult?(.failure(MailError.cancelled))
            }
            parent.dismiss()
        }
    }

    enum MailError: Error, LocalizedError {
        case cancelled
        case notAvailable

        var errorDescription: String? {
            switch self {
            case .cancelled: return "邮件发送已取消"
            case .notAvailable: return "设备未配置邮件账户"
            }
        }
    }
}

/// 检查邮件是否可用
var canSendMail: Bool {
    MFMailComposeViewController.canSendMail()
}
