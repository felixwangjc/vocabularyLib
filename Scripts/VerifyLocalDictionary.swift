import Foundation

@main
struct VerifyLocalDictionary {
    static func main() {
        let dictionary = LocalDictionary(databaseURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let start = Date()
        for word in ["apple", "witty", "firmly", "established", "serendipity", "Apple", "don't"] {
            guard let entry = dictionary.lookup(word) else { fatalError("Missing word: \(word)") }
            precondition(!entry.chineseDefinition.isEmpty)
            precondition(entry.needsExample)
        }
        precondition(dictionary.lookup("no-such-word-xyzzy-qwerty") == nil)
        precondition(dictionary.lookup("' OR 1=1 --") == nil)
        let missing = LocalDictionary(databaseURL: URL(fileURLWithPath: "/private/tmp/nonexistent-vocabulary.sqlite"))
        precondition(missing.lookup("apple") == nil)
        let book = dictionary.lookup("book")!
        precondition(book.groupedMeanings.map(\.partOfSpeech) == ["noun", "verb", "other"])
        precondition(book.groupedMeanings[0].englishDefinitions.count == 4)
        precondition(book.groupedMeanings[1].chineseDefinitions.contains { $0.contains("预订") })
        precondition(book.groupedMeanings[1].englishDefinitions.isEmpty, "Do not assign noun definitions to verbs")
        let light = dictionary.lookup("light")!
        precondition(Set(light.groupedMeanings.map(\.partOfSpeech)).isSuperset(of: ["noun", "adjective", "verb", "adverb"]))
        precondition(dictionary.lookup("firmly")!.groupedMeanings.first?.partOfSpeech == "adverb")
        let roundTrip = try! JSONDecoder().decode(WordEntry.self, from: JSONEncoder().encode(book))
        precondition(roundTrip == book, "All POS groups must survive storage")
        var legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as! [String: Any]
        legacy.removeValue(forKey: "meanings")
        let oldEntry = try! JSONDecoder().decode(WordEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldEntry.meanings == nil && oldEntry.id == book.id)
        precondition(oldEntry.groupedMeanings == book.groupedMeanings, "Legacy data remains readable")
        print("Local lookup checks passed in \(Date().timeIntervalSince(start))s (no network).")
    }
}
