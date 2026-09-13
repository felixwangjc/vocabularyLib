import SwiftUI

enum AppTheme {
    static let accent = Color(red: 1.00, green: 0.38, blue: 0.04)
    static let accentSoft = Color(red: 1.00, green: 0.91, blue: 0.80)
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.10)
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.072, blue: 0.065, alpha: 1)
            : UIColor(red: 0.985, green: 0.982, blue: 0.945, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.125, blue: 0.115, alpha: 1)
            : UIColor.white
    })
    static let mint = adaptive(light: (0.86, 0.92, 0.77), dark: (0.15, 0.24, 0.18))
    static let sky = adaptive(light: (0.83, 0.93, 0.94), dark: (0.13, 0.23, 0.25))
    static let lemon = adaptive(light: (0.97, 0.94, 0.72), dark: (0.25, 0.22, 0.12))
    static let lilac = adaptive(light: (0.91, 0.84, 0.94), dark: (0.23, 0.17, 0.27))
    static let peach = adaptive(light: (1.00, 0.90, 0.79), dark: (0.27, 0.17, 0.12))

    static func pastel(_ index: Int) -> Color {
        [mint, sky, lemon, lilac, peach][((index % 5) + 5) % 5]
    }

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

struct LearningBackground: View {
    var body: some View {
        ZStack {
            AppTheme.canvas
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 80)
                    .fill(AppTheme.lemon.opacity(0.28))
                    .frame(width: proxy.size.width * 0.78, height: 105)
                    .rotationEffect(.degrees(-20))
                    .offset(x: -proxy.size.width * 0.25, y: 45)
                RoundedRectangle(cornerRadius: 80)
                    .fill(AppTheme.mint.opacity(0.20))
                    .frame(width: proxy.size.width * 0.78, height: 90)
                    .rotationEffect(.degrees(-20))
                    .offset(x: proxy.size.width * 0.50, y: proxy.size.height * 0.45)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func studyCard(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
    }

    func learningScreenBackground() -> some View {
        background { LearningBackground() }
    }
}
