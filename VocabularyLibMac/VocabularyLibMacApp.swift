import SwiftUI

@main
struct VocabularyLibMacApp: App {
    @StateObject private var store = VocabularyStore()

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(store)
                .tint(MacTheme.accent)
                .task { await store.upgradeLegacyMeanings() }
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
