import SwiftUI

@main
struct VocabularyLibMacApp: App {
    @StateObject private var store = VocabularyStore()
    @StateObject private var dailySlang = DailySlangStore()

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .modifier(CheckInLifecycle())
                .modifier(DailySlangSplash(store: dailySlang))
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
