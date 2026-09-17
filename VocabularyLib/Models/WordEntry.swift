import Foundation

struct ReadingContext: Identifiable, Codable, Hashable {
    var id = UUID()
    var sentence: String
    var bookTitle = ""
    var page = ""
    var note = ""
    /// Snapshot of the exact sense selected for this occurrence, not just its POS.
    var selectedMeaning: String?
    var createdAt = Date()

    func hasSameContent(as other: ReadingContext) -> Bool {
        sentence == other.sentence && bookTitle == other.bookTitle && page == other.page
    }
}

struct OCRTextLine {
    let text: String
    let box: CGRect
}

enum OCRSentenceExtractor {
    /// Join nearby, aligned lines only. Never join across a column or a large paragraph gap.
    /// Cropped/incomplete sentences remain editable OCR excerpts, not invented completions.
    static func sentence(lines: [OCRTextLine], lineIndex: Int, wordRange: Range<String.Index>) -> String {
        let line = lines[lineIndex]
        let targetOffset = line.text.distance(from: line.text.startIndex, to: wordRange.lowerBound)
        func adjacent(_ upper: OCRTextLine, _ lower: OCRTextLine) -> Bool {
            let height = max(upper.box.height, lower.box.height)
            let overlap = min(upper.box.maxX, lower.box.maxX) - max(upper.box.minX, lower.box.minX)
            let gap = upper.box.minY - lower.box.maxY
            return upper.box.midY > lower.box.midY && gap >= -height * 0.3 && gap < height * 1.5
                && abs(upper.box.minX - lower.box.minX) < max(0.04, height * 2)
                && overlap > min(upper.box.width, lower.box.width) * 0.5
        }
        var start = lineIndex
        var end = lineIndex
        while start > 0, lineIndex - start < 8, adjacent(lines[start - 1], lines[start]) { start -= 1 }
        while end + 1 < lines.count, end - lineIndex < 8, adjacent(lines[end], lines[end + 1]) { end += 1 }
        let preceding = lines[start..<lineIndex].map { $0.text + " " }.joined()
        let paragraph = lines[start...end].map(\.text).joined(separator: " ")
        let target = paragraph.index(paragraph.startIndex, offsetBy: preceding.count + targetOffset)
        var result = line.text
        paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { text, range, _, stop in
            if range.contains(target), let text { result = text; stop = true }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WordEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let word: String
    let phonetic: String
    let chineseDefinition: String
    let englishDefinition: String
    var example: String
    var meanings: [WordMeaning]?
    var tags: [String]?
    var readingContexts: [ReadingContext]?
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
