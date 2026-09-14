import SwiftUI

enum MacTheme {
    static let accent = adaptive(
        light: NSColor(red: 1.00, green: 0.38, blue: 0.04, alpha: 1),
        dark: NSColor(red: 1.00, green: 0.55, blue: 0.24, alpha: 1)
    )
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let mint = adaptive(
        light: NSColor(red: 0.86, green: 0.92, blue: 0.77, alpha: 1),
        dark: NSColor(red: 0.12, green: 0.24, blue: 0.16, alpha: 1)
    )
    static let sky = adaptive(
        light: NSColor(red: 0.83, green: 0.93, blue: 0.94, alpha: 1),
        dark: NSColor(red: 0.10, green: 0.22, blue: 0.25, alpha: 1)
    )
    static let lemon = adaptive(
        light: NSColor(red: 0.97, green: 0.94, blue: 0.72, alpha: 1),
        dark: NSColor(red: 0.25, green: 0.22, blue: 0.09, alpha: 1)
    )
    static let lilac = adaptive(
        light: NSColor(red: 0.91, green: 0.84, blue: 0.94, alpha: 1),
        dark: NSColor(red: 0.23, green: 0.16, blue: 0.27, alpha: 1)
    )
    static let peach = adaptive(
        light: NSColor(red: 1.00, green: 0.90, blue: 0.79, alpha: 1),
        dark: NSColor(red: 0.29, green: 0.17, blue: 0.10, alpha: 1)
    )
    static let monogram = adaptive(
        light: NSColor(white: 1, alpha: 0.70),
        dark: NSColor(white: 1, alpha: 0.09)
    )

    static func pastel(_ index: Int) -> Color {
        [mint, sky, lemon, lilac, peach][((index % 5) + 5) % 5]
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    func macCard(_ color: Color = MacTheme.surface, cornerRadius: CGFloat = 24) -> some View {
        foregroundStyle(.primary)
            .background(color, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
    }
}
