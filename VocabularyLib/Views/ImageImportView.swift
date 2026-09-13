import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

/// The system pickers only grant access to the image explicitly selected by the user.
struct ImageImportView: View {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var showsFiles = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("从相册导入", systemImage: "photo.on.rectangle")
                    }
                    Button { showsFiles = true } label: {
                        Label("从文件导入", systemImage: "folder")
                    }
                } header: {
                    Text("选择图片来源")
                } footer: {
                    Text("支持照片、截图及常见图片文件；识别结果支持缩放和长按 2 秒添加单词。")
                }
                .disabled(isLoading)
                if isLoading { ProgressView("正在读取图片…") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("导入图片识词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                isLoading = true
                errorMessage = nil
                importTask = Task {
                    do {
                        let image = try await ImportedImageLoader.loadFile(url)
                        try Task.checkCancellation()
                        finish(image)
                    }
                    catch is CancellationError { }
                    catch { fail(error) }
                }
            case .failure(let error): fail(error)
            }
        }
        .task(id: photo) {
            guard let photo else { return }
            isLoading = true
            errorMessage = nil
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else {
                    throw ImageImportError.unreadable
                }
                let image = try await ImportedImageLoader.decode(data)
                try Task.checkCancellation()
                finish(image)
            } catch is CancellationError {
                isLoading = false
            } catch { fail(error) }
        }
        .onDisappear { importTask?.cancel() }
    }

    private func finish(_ image: UIImage) {
        isLoading = false
        onImage(image)
        dismiss()
    }

    private func fail(_ error: Error) {
        isLoading = false
        errorMessage = "无法导入图片：\(error.localizedDescription)"
    }
}

private enum ImageImportError: LocalizedError {
    case unreadable, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: return "图片格式不受支持或文件已损坏。"
        case .tooLarge: return "图片超过 50 MB，请选择较小的图片。"
        }
    }
}

actor ImportedImageLoader {
    static let shared = ImportedImageLoader()

    static func decode(_ data: Data) async throws -> UIImage { try await shared.decoded(data) }
    static func loadFile(_ url: URL) async throws -> UIImage { try await shared.file(url) }
    static func prepare(_ image: UIImage) async throws -> UIImage { try await shared.prepared(image) }

    private func file(_ url: URL) throws -> UIImage {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 50 * 1024 * 1024 {
            throw ImageImportError.tooLarge
        }
        return try decoded(Data(contentsOf: url, options: .mappedIfSafe))
    }

    private func prepared(_ image: UIImage) throws -> UIImage {
        guard let data = image.jpegData(compressionQuality: 0.95) else { throw ImageImportError.unreadable }
        return try decoded(data)
    }

    private func decoded(_ data: Data) throws -> UIImage {
        guard data.count <= 50 * 1024 * 1024 else { throw ImageImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImageImportError.unreadable }
        return UIImage(cgImage: image)
    }
}
