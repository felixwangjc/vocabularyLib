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
                    var entry = WordEntry(word: word, phonetic: "", chineseDefinition: word == "book" ? "n. 书\nv. 预订" : "测试释义",
                              englishDefinition: word == "book" ? "n. A written work.\nv. To reserve." : "A review test word.", example: "This is a \(word).",
                              createdAt: Date(timeIntervalSince1970: Double(index)))
                    if ProcessInfo.processInfo.environment["READING_CONTEXT_UI_TEST"] == "1" {
                        entry.readingContexts = [ReadingContext(sentence: "I read about \(word).", bookTitle: "Test Reader", page: "12")]
                    }
                    return entry
                }
                defaults.set(try? JSONEncoder().encode(words), forKey: "vocabulary.entries.v1")
                let mode = ProcessInfo.processInfo.environment["EXERCISE_UI_TEST_MODE"]
                    .flatMap(ExerciseMode.init(rawValue:)) ?? .recognition
                let records = Dictionary(uniqueKeysWithValues: words.map { entry in
                    var exercise = WordExercise(mode: mode, word: entry.word)
                    if mode == .missingLetters { exercise.missingIndices = [1, 3]; exercise.refreshCandidates(word: entry.word) }
                    var record = ReviewRecord()
                    record.pendingExercise = exercise
                    return (entry.id.uuidString, record)
                })
                defaults.set(try? JSONEncoder().encode(records), forKey: "vocabulary.reviews.v1")
            }
            return VocabularyStore(defaults: defaults)
        }
        #endif
        return VocabularyStore()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .preferredColorScheme(ProcessInfo.processInfo.environment["UI_TEST_DARK"] == "1" ? .dark : nil)
                #endif
                .environmentObject(store)
                .tint(AppTheme.accent)
                .task { await store.upgradeLegacyMeanings() }
        }
    }
}
