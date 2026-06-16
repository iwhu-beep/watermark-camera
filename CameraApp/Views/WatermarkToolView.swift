//
//  WatermarkToolView.swift
//  CameraApp
//
//  水印工具：选择图片 + 输入水印数据 → 生成带水印图片
//  路径: CameraApp/Views/WatermarkToolView.swift
//

import SwiftUI
import Photos
import PhotosUI

struct WatermarkToolView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings

    // MARK: - 状态

    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker: Bool = false
    @State private var watermarkText: String = ""
    @State private var fontSize: CGFloat = 24
    @State private var verticalPosition: Double = 0.15
    @State private var showSaveResult: Bool = false
    @State private var saveResultMessage: String = ""
    @State private var showExportOptions: Bool = false

    // 预览用
    @State private var watermarkedImage: UIImage? = nil

    // MARK: - 视图

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 图片选择区域
                    imageSection

                    if selectedImage != nil {
                        // 水印输入区域
                        watermarkInputSection

                        // 预览区域
                        previewSection

                        // 操作按钮
                        actionButtons
                    }
                }
                .padding()
            }
            .navigationTitle("水印工具")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .alert("结果", isPresented: $showSaveResult) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(saveResultMessage)
            }
            .onChange(of: watermarkText) { _ in updatePreview() }
            .onChange(of: fontSize) { _ in updatePreview() }
            .onChange(of: verticalPosition) { _ in updatePreview() }
            .onChange(of: selectedImage) { _ in updatePreview() }
        }
    }

    // MARK: - 图片选择

    private var imageSection: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .onTapGesture { showImagePicker = true }

                    Button(action: { selectedImage = nil; watermarkedImage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .padding(8)
                }
            } else {
                Button(action: { showImagePicker = true }) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("点击选择图片")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("从相册选择要添加水印的图片")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - 水印输入

    private var watermarkInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("水印内容")
                    .font(.headline)
                Spacer()
                Button("从当前定位填充") {
                    fillFromCurrentData()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            TextEditor(text: $watermarkText)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            Text("每行一条信息，格式如：经度：116.407400")
                .font(.caption)
                .foregroundColor(.secondary)

            // 字号调整
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("水印大小")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(fontSize))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $fontSize, in: 12...80, step: 2)
            }

            // 垂直位置
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("垂直位置")
                        .font(.subheadline)
                    Spacer()
                    Text(positionLabel)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $verticalPosition, in: 0...1, step: 0.05)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - 预览

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预览效果")
                .font(.headline)

            if let preview = watermarkedImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                    .shadow(radius: 2)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(Text("生成中...").foregroundColor(.secondary))
            }
        }
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: saveToLibrary) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("保存到相册")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Button(action: { showExportOptions = true }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享/上传")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .sheet(isPresented: $showExportOptions) {
            if let image = watermarkedImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - 方法

    private func updatePreview() {
        guard let image = selectedImage, !watermarkText.isEmpty else {
            watermarkedImage = nil
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let lines = watermarkText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let fontSizeScale = fontSize / 24.0

            let result = ImageWatermark.draw(
                on: image,
                lines: lines,
                fontSizeScale: fontSizeScale,
                verticalPosition: verticalPosition
            )

            DispatchQueue.main.async {
                watermarkedImage = result
            }
        }
    }

    private func fillFromCurrentData() {
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("经度：---")
        lines.append("纬度：---")
        lines.append("坐标：WGS84 坐标系")
        lines.append("地址：---")
        lines.append("时间：\(f.string(from: now))")
        if !settings.noteText.isEmpty {
            lines.append("备注：\(settings.noteText)")
        }

        watermarkText = lines.joined(separator: "\n")
    }

    private func saveToLibrary() {
        guard let image = watermarkedImage ?? selectedImage else { return }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            DispatchQueue.main.async {
                saveResultMessage = success ? "已保存到相册" : "保存失败: \(error?.localizedDescription ?? "未知错误")"
                showSaveResult = true
            }
        }
    }

    private var positionLabel: String {
        let pos = verticalPosition
        if pos < 0.2 { return "底部" }
        else if pos < 0.4 { return "偏下" }
        else if pos < 0.6 { return "居中" }
        else if pos < 0.8 { return "偏上" }
        else { return "顶部" }
    }
}

// MARK: - 图片选择器

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }

            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    self.parent.image = image as? UIImage
                }
            }
        }
    }
}

// MARK: - 分享表

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
