//
//  BaiduAuthView.swift
//  CameraApp
//
//  百度网盘 OAuth 授权页面
//  路径: CameraApp/Views/BaiduAuthView.swift
//

import SwiftUI
import WebKit

struct BaiduAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authResult: String?
    @State private var isLoading = true
    @State private var showCodeInput = false
    @State private var authCode = ""

    var onAuthComplete: ((Bool, String) -> Void)?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showCodeInput {
                    // 手动输入授权码
                    VStack(spacing: 16) {
                        Text("请输入授权码")
                            .font(.headline)
                            .padding(.top, 40)

                        TextField("授权码", text: $authCode)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .padding(.horizontal, 40)

                        Button(action: submitCode) {
                            Text("确认授权")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 40)
                        .disabled(authCode.isEmpty)

                        if let result = authResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("成功") ? .green : .red)
                                .padding()
                        }

                        Spacer()
                    }
                } else {
                    // WebView 授权
                    ZStack {
                        BaiduWebView(
                            url: BaiduUploader.shared.authorizationURL(),
                            onAuthCode: { code in
                                authCode = code
                                showCodeInput = true
                                exchangeCode(code)
                            },
                            onLoadComplete: { isLoading = false }
                        )
                        .ignoresSafeArea(edges: .bottom)

                        if isLoading {
                            ProgressView("加载中...")
                                .padding()
                                .background(.regularMaterial)
                                .cornerRadius(8)
                        }
                    }
                }

                if let result = authResult, !showCodeInput {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("成功") ? .green : .red)
                        .padding()
                }
            }
            .navigationTitle("百度网盘登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("手动输入") {
                        showCodeInput = true
                    }
                }
            }
        }
    }

    // MARK: - 手动输入授权码

    private func submitCode() {
        exchangeCode(authCode)
    }

    // MARK: - 换取 Token

    private func exchangeCode(_ code: String) {
        authResult = "正在验证..."
        BaiduUploader.shared.exchangeCodeForToken(code: code) { success, message in
            authResult = message
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    onAuthComplete?(true, message)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - WebView 包装

struct BaiduWebView: UIViewRepresentable {
    let url: URL
    let onAuthCode: (String) -> Void
    let onLoadComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthCode: onAuthCode, onLoadComplete: onLoadComplete)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let onAuthCode: (String) -> Void
        let onLoadComplete: () -> Void

        init(onAuthCode: @escaping (String) -> Void, onLoadComplete: @escaping () -> Void) {
            self.onAuthCode = onAuthCode
            self.onLoadComplete = onLoadComplete
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadComplete()

            // 检查页面是否包含授权码
            webView.evaluateJavaScript("document.body.innerText") { result, _ in
                if let text = result as? String {
                    // 查找授权码（通常在页面中显示）
                    if let code = self.extractCode(from: text) {
                        self.onAuthCode(code)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 检查重定向 URL
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString
                // oob 模式下，授权成功后会跳转到包含 code 的 URL
                if urlString.contains("code=") || urlString.contains("auth_code=") {
                    if let code = self.extractCodeFromURL(url) {
                        onAuthCode(code)
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }

        private func extractCode(from text: String) -> String? {
            // 百度授权码通常是 32 位字母数字
            let patterns = [
                "授权码[：:]\\s*([a-zA-Z0-9]{20,})",
                "code[：:]\\s*([a-zA-Z0-9]{20,})",
                "([a-f0-9]{32})"
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range(at: 1), in: text) {
                    return String(text[range])
                }
            }
            return nil
        }

        private func extractCodeFromURL(_ url: URL) -> String? {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            return components.queryItems?.first(where: { $0.name == "code" || $0.name == "auth_code" })?.value
        }
    }
}
