import SwiftUI

enum AppTheme {
    static let accent = Color.teal
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

extension View {
    func studyCard() -> some View {
        self
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}
