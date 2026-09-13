import Foundation

@main
struct VerifyMeaningMigration {
    @MainActor
    static func main() async throws {
        let domain = "com.vocabularylib.migration-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let entry = WordEntry(word: "book", phonetic: "", chineseDefinition: "n. 书\nv. 预订",
                              englishDefinition: "n. A written work.", example: "Keep my example.")
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        object.removeValue(forKey: "meanings")
        defaults.set(try JSONSerialization.data(withJSONObject: [object]), forKey: "vocabulary.entries.v1")
        var review = ReviewRecord()
        review.answer(remembered: true, now: Date())
        defaults.set(try JSONEncoder().encode([entry.id.uuidString: review]), forKey: "vocabulary.reviews.v1")

        let store = VocabularyStore(defaults: defaults)
        precondition(store.entries[0].meanings == nil)
        await store.upgradeLegacyMeanings()
        let updated = store.entries[0]
        precondition(updated.id == entry.id && updated.createdAt == entry.createdAt)
        precondition(updated.example == entry.example)
        precondition(updated.groupedMeanings.map(\.partOfSpeech) == ["noun", "verb"])
        let restored = VocabularyStore(defaults: defaults)
        precondition(restored.entries[0] == updated)
        precondition(restored.reviews[entry.id.uuidString]?.reviewCount == 1)
        precondition(restored.reviews[entry.id.uuidString]?.dueAt == review.dueAt)
        print("Meaning migration passed: legacy decoding, grouped persistence, and unchanged review history.")
    }
}
