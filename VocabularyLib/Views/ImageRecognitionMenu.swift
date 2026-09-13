import SwiftUI
import UIKit

/// Toolbar labels may be converted into native bar items; SwiftUI geometry callbacks
/// on those labels are not guaranteed. Read the actual tapped view in window space.
struct ImageMenuButton: UIViewRepresentable {
    let tapped: (CGRect) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(tapped: tapped) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "text.viewfinder"), for: .normal)
        button.tintColor = UIColor(AppTheme.accent)
        button.backgroundColor = UIColor(AppTheme.accentSoft)
        button.layer.cornerRadius = 16
        button.accessibilityLabel = "图片识词"
        button.accessibilityIdentifier = "imageRecognitionTrigger"
        button.accessibilityHint = "展开拍照、粘贴和导入图片菜单"
        button.addTarget(context.coordinator, action: #selector(Coordinator.press(_:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.tapped = tapped
        button.tintColor = UIColor(AppTheme.accent)
        button.backgroundColor = UIColor(AppTheme.accentSoft)
    }

    final class Coordinator: NSObject {
        var tapped: (CGRect) -> Void
        init(tapped: @escaping (CGRect) -> Void) { self.tapped = tapped }
        @objc func press(_ sender: UIButton) {
            tapped(sender.convert(sender.bounds, to: nil))
        }
    }
}

/// Expands into the lower-left quadrant from the top-right corner.
struct ImageRecognitionMenu: View {
    static let size: CGFloat = 160
    let camera: () -> Void
    let paste: () -> Void
    let importImage: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            action("拍照", icon: "camera.fill", x: 63, y: 26, perform: camera)
            action("粘贴", icon: "doc.on.clipboard.fill", x: 87, y: 78, perform: paste)
            action("导入", icon: "folder.fill", x: 139, y: 102, perform: importImage)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("图片识词")
        .accessibilityAction(.escape, dismiss)
    }

    private func action(_ title: String, icon: String, x: CGFloat, y: CGFloat, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .medium))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 48, height: 48)
            .background(AppTheme.surface, in: Circle())
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .position(x: x, y: y)
    }
}
