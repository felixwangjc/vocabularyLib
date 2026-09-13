import Foundation

struct WordEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let word: String
    let phonetic: String
    let chineseDefinition: String
    let englishDefinition: String
    var example: String
    var meanings: [WordMeaning]?
    let audioURL: URL?
    let createdAt: Date

    var needsExample: Bool {
        example.isEmpty || example == "I learned the word ‘\(word)’ today."
    }

    init(
        id: UUID = UUID(),
        word: String,
        phonetic: String,
        chineseDefinition: String,
        englishDefinition: String,
        example: String,
        meanings: [WordMeaning]? = nil,
        audioURL: URL? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.chineseDefinition = chineseDefinition
        self.englishDefinition = englishDefinition
        self.example = example
        self.meanings = meanings ?? WordMeaning.parse(chinese: chineseDefinition, english: englishDefinition)
        self.audioURL = audioURL
        self.createdAt = createdAt
    }

    var groupedMeanings: [WordMeaning] {
        meanings ?? WordMeaning.parse(chinese: chineseDefinition, english: englishDefinition)
    }
}

/// Chinese and English senses are grouped by POS, not paired by array index:
/// ECDICT's two languages can have different numbers and ordering of senses.
struct WordMeaning: Codable, Hashable, Identifiable {
    let partOfSpeech: String
    var chineseDefinitions: [String] = []
    var englishDefinitions: [String] = []
    var id: String { partOfSpeech }

    var title: String {
        switch partOfSpeech {
        case "noun": return "名词 · n."
        case "verb": return "动词 · v."
        case "adjective": return "形容词 · adj."
        case "adverb": return "副词 · adv."
        case "pronoun": return "代词 · pron."
        case "preposition": return "介词 · prep."
        case "conjunction": return "连词 · conj."
        case "interjection": return "感叹词 · interj."
        case "numeral": return "数词 · num."
        case "determiner": return "限定词 · det."
        case "article": return "冠词 · art."
        case "other": return "其他释义 / 补充说明"
        default: return partOfSpeech
        }
    }

    static func normalizedPOS(_ raw: String) -> String {
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "") {
        case "n", "noun": return "noun"
        case "v", "vt", "vi", "verb": return "verb"
        case "a", "s", "adj", "adjective": return "adjective"
        case "r", "adv", "ad", "adverb": return "adverb"
        case "pron", "pronoun": return "pronoun"
        case "prep", "preposition": return "preposition"
        case "conj", "conjunction": return "conjunction"
        case "int", "interj", "interjection": return "interjection"
        case "num", "numeral": return "numeral"
        case "det", "determiner": return "determiner"
        case "art", "article": return "article"
        case "": return "other"
        default: return raw.lowercased()
        }
    }

    static func parse(chinese: String, english: String) -> [WordMeaning] {
        let pattern = #"^(n|vt|vi|v|adj|adv|ad|a|s|r|pron|prep|conj|interj|int|num|det|art)\.?\s+(.+)$"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        var groups: [WordMeaning] = []
        for (text, isChinese) in [(chinese, true), (english, false)] {
            for rawLine in text.replacingOccurrences(of: "\\n", with: "\n").components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                var pos = "other"
                var definition = line
                if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let tagRange = Range(match.range(at: 1), in: line),
                   let textRange = Range(match.range(at: 2), in: line) {
                    let tag = String(line[tagRange]).lowercased()
                    pos = normalizedPOS(tag)
                    definition = (tag == "vt" || tag == "vi" ? "\(tag). " : "") + String(line[textRange])
                }
                if !groups.contains(where: { $0.partOfSpeech == pos }) { groups.append(WordMeaning(partOfSpeech: pos)) }
                let index = groups.firstIndex(where: { $0.partOfSpeech == pos })!
                if isChinese {
                    if !groups[index].chineseDefinitions.contains(definition) { groups[index].chineseDefinitions.append(definition) }
                } else if !groups[index].englishDefinitions.contains(definition) {
                    groups[index].englishDefinitions.append(definition)
                }
            }
        }
        return groups.filter { $0.partOfSpeech != "other" } + groups.filter { $0.partOfSpeech == "other" }
    }
}
