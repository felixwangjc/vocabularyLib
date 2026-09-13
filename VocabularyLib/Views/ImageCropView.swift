import SwiftUI
import UIKit

struct ImageCropView: View {
    let image: UIImage
    let completion: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ImageCropModel
    @State private var aspect: CropAspect = .original

    init(image: UIImage, completion: @escaping (UIImage) -> Void) {
        self.image = image
        self.completion = completion
        _model = StateObject(wrappedValue: ImageCropModel(image: image))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                GeometryReader { proxy in
                    let viewport = CropAspect.fit(
                        ratio: aspect.ratio(for: model.image.size),
                        inside: CGSize(width: max(proxy.size.width - 32, 1), height: max(proxy.size.height - 12, 1))
                    )
                    ZStack {
                        Color.black
                        CropCanvas(model: model, viewport: viewport)
                            .frame(width: viewport.width, height: viewport.height)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("裁剪预览")
                            .accessibilityIdentifier("cropCanvas")
                            .overlay { CropGrid().allowsHitTesting(false) }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                            .shadow(color: .black.opacity(0.35), radius: 20)
                    }
                    .onAppear { model.setViewport(viewport) }
                    .onChange(of: viewport) { _, value in model.setViewport(value) }
                }

                Picker("裁剪比例", selection: $aspect) {
                    ForEach(CropAspect.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                .onChange(of: aspect) { _, _ in model.reset() }
                .padding(.horizontal, 16)

                Label("拖动调整位置，双指缩放图片", systemImage: "hand.draw")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("裁剪识别区域")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用此区域") {
                        guard let cropped = model.croppedImage() else { return }
                        completion(cropped)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(AppTheme.accent)
    }
}

@MainActor
final class ImageCropModel: ObservableObject {
    let image: UIImage
    @Published var zoom: CGFloat = 1
    @Published var offset: CGSize = .zero
    private(set) var viewport: CGSize = .zero
    private var settledZoom: CGFloat = 1
    private var settledOffset: CGSize = .zero

    init(image: UIImage) {
        self.image = image.normalizedForCropping
    }

    func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewport = size
        clampOffset()
    }

    func reset() {
        zoom = 1
        offset = .zero
        settledZoom = 1
        settledOffset = .zero
    }

    func magnify(_ value: CGFloat) {
        zoom = min(max(settledZoom * value, 1), 8)
        clampOffset()
    }

    func finishMagnifying() {
        settledZoom = zoom
        settledOffset = offset
    }

    func drag(_ translation: CGSize) {
        offset = CGSize(
            width: settledOffset.width + translation.width,
            height: settledOffset.height + translation.height
        )
        clampOffset()
    }

    func finishDragging() {
        settledOffset = offset
    }

    func displaySize(for viewport: CGSize) -> CGSize {
        let imageRatio = max(image.size.width / max(image.size.height, 1), 0.001)
        let viewportRatio = viewport.width / max(viewport.height, 1)
        let base = viewportRatio > imageRatio
            ? CGSize(width: viewport.width, height: viewport.width / imageRatio)
            : CGSize(width: viewport.height * imageRatio, height: viewport.height)
        return CGSize(width: base.width * zoom, height: base.height * zoom)
    }

    func croppedImage() -> UIImage? {
        guard let source = image.cgImage, viewport.width > 0, viewport.height > 0 else { return nil }
        let display = displaySize(for: viewport)
        let normalized = CGRect(
            x: ((display.width - viewport.width) / 2 - offset.width) / display.width,
            y: ((display.height - viewport.height) / 2 - offset.height) / display.height,
            width: viewport.width / display.width,
            height: viewport.height / display.height
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixels = CGRect(
            x: normalized.minX * CGFloat(source.width),
            y: normalized.minY * CGFloat(source.height),
            width: normalized.width * CGFloat(source.width),
            height: normalized.height * CGFloat(source.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: CGFloat(source.width), height: CGFloat(source.height)))
        guard pixels.width >= 2, pixels.height >= 2, let result = source.cropping(to: pixels) else { return nil }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }

    private func clampOffset() {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let display = displaySize(for: viewport)
        let horizontal = max(0, (display.width - viewport.width) / 2)
        let vertical = max(0, (display.height - viewport.height) / 2)
        offset.width = min(max(offset.width, -horizontal), horizontal)
        offset.height = min(max(offset.height, -vertical), vertical)
    }
}

private struct CropCanvas: View {
    @ObservedObject var model: ImageCropModel
    let viewport: CGSize

    var body: some View {
        let display = model.displaySize(for: viewport)
        Image(uiImage: model.image)
            .resizable()
            .frame(width: display.width, height: display.height)
            .offset(model.offset)
            .frame(width: viewport.width, height: viewport.height)
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged(model.magnify)
                    .onEnded { _ in model.finishMagnifying() }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { model.drag($0.translation) }
                    .onEnded { _ in model.finishDragging() }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) { model.reset() }
            }
    }
}

private struct CropGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    path.move(to: CGPoint(x: proxy.size.width * fraction, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width * fraction, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: proxy.size.height * fraction))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * fraction))
                }
            }
            .stroke(.white.opacity(0.42), lineWidth: 0.8)
        }
    }
}

private enum CropAspect: String, CaseIterable, Identifiable {
    case original, square, landscape, portrait
    var id: Self { self }
    var title: String {
        switch self {
        case .original: return "原比例"
        case .square: return "1:1"
        case .landscape: return "4:3"
        case .portrait: return "3:4"
        }
    }

    func ratio(for imageSize: CGSize) -> CGFloat {
        switch self {
        case .original: return max(imageSize.width / max(imageSize.height, 1), 0.01)
        case .square: return 1
        case .landscape: return 4 / 3
        case .portrait: return 3 / 4
        }
    }

    static func fit(ratio: CGFloat, inside bounds: CGSize) -> CGSize {
        if bounds.width / max(bounds.height, 1) > ratio {
            return CGSize(width: bounds.height * ratio, height: bounds.height)
        }
        return CGSize(width: bounds.width, height: bounds.width / ratio)
    }
}

private extension UIImage {
    var normalizedForCropping: UIImage {
        guard imageOrientation != .up || scale != 1 else { return self }
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}
