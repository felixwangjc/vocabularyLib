import SwiftUI

@main
struct VocabularyLibApp: App {
    @StateObject private var store = makeStore()

    private static func makeStore() -> VocabularyStore {
        #if DEBUG
        // UI tests use a separate domain and never modify the user's vocabulary.
        if let testID = ProcessInfo.processInfo.environment["REVIEW_UI_TEST_ID"],
           UUID(uuidString: testID) != nil,
           let defaults = UserDefaults(suiteName: "com.vocabularylib.review-tests.\(testID)") {
            if defaults.data(forKey: "vocabulary.entries.v1") == nil {
                let words = ["apple", "book", "cloud"].enumerated().map { index, word in
                    WordEntry(word: word, phonetic: "", chineseDefinition: word == "book" ? "n. 书\nv. 预订" : "测试释义",
                              englishDefinition: word == "book" ? "n. A written work.\nv. To reserve." : "A review test word.", example: "This is a \(word).",
                              createdAt: Date(timeIntervalSince1970: Double(index)))
                }
                defaults.set(try? JSONEncoder().encode(words), forKey: "vocabulary.entries.v1")
            }
            return VocabularyStore(defaults: defaults)
        }
        #endif
        return VocabularyStore()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(AppTheme.accent)
                .task { await store.upgradeLegacyMeanings() }
        }
    }
}
