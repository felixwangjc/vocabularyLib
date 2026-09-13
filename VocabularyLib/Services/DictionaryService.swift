import Foundation

enum DictionaryServiceError: LocalizedError {
    case invalidWord
    case wordNotFound
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidWord: return "请输入有效的英文单词。"
        case .wordNotFound: return "没有找到这个单词，请检查拼写后再试。"
        case .server(let code): return code == 429 ? "例句服务请求过多，请稍后重试。" : "词典服务暂不可用（\(code)），请稍后重试。"
        case .invalidResponse: return "词典服务返回了无法解析的数据，请稍后重试。"
        }
    }
}

actor DictionaryService {
    private let local: LocalDictionary
    private let session: URLSession
    private var cachedEntries: [String: [DictionaryResponse]] = [:]

    init(local: LocalDictionary = LocalDictionary(), session: URLSession? = nil) {
        self.local = local
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 6
            configuration.timeoutIntervalForResource = 10
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }
    private struct DictionaryResponse: Decodable {
        let word: String
        let phonetic: String?
        let phonetics: [Phonetic]?
        let meanings: [Meaning]
    }

    private struct Phonetic: Decodable {
        let text: String?
        let audio: String?
    }

    private struct Meaning: Decodable {
        let partOfSpeech: String?
        let definitions: [Definition]
    }

    private struct Definition: Decodable {
        let definition: String
        let example: String?
    }

    private struct TranslationResponse: Decodable {
        let responseData: TranslationData?
        struct TranslationData: Decodable { let translatedText: String? }
    }

    func lookup(_ rawWord: String) async throws -> WordEntry {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard word.range(of: "^[a-z]+(?:[-'][a-z]+)*$", options: .regularExpression) != nil else {
            throw DictionaryServiceError.invalidWord
        }

        if let entry = local.lookup(word) { return entry }
        let entries = try await onlineEntries(word)
        guard let entry = entries.first else { throw DictionaryServiceError.wordNotFound }
        var groups: [WordMeaning] = []
        for meaning in entries.flatMap(\.meanings) {
            let pos = WordMeaning.normalizedPOS(meaning.partOfSpeech ?? "")
            if !groups.contains(where: { $0.partOfSpeech == pos }) { groups.append(WordMeaning(partOfSpeech: pos)) }
            let index = groups.firstIndex(where: { $0.partOfSpeech == pos })!
            for sense in meaning.definitions {
                let text = sense.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, !groups[index].englishDefinitions.contains(text) {
                    groups[index].englishDefinitions.append(text)
                }
            }
        }
        groups.removeAll { $0.englishDefinitions.isEmpty }
        guard !groups.isEmpty else { throw DictionaryServiceError.wordNotFound }
        // Translate POS groups concurrently, keeping their original order and all English senses.
        let untranslated = groups
        await withTaskGroup(of: (Int, String).self) { tasks in
            for (index, meaning) in untranslated.enumerated() {
                tasks.addTask {
                    (index, await self.translatedDefinition(for: meaning.englishDefinitions.joined(separator: "\n")))
                }
            }
            for await (index, translation) in tasks { groups[index].chineseDefinitions = [translation] }
        }
        return WordEntry(word: word,
                         phonetic: entry.phonetic ?? entry.phonetics?.compactMap(\.text).first ?? "",
                         chineseDefinition: groups.flatMap(\.chineseDefinitions).joined(separator: "\n"),
                         englishDefinition: groups.flatMap(\.englishDefinitions).joined(separator: "\n"),
                         example: entries.compactMap { example(in: $0) }.first ?? "",
                         meanings: groups)
    }

    func localMeanings(for word: String) -> [WordMeaning]? { local.lookup(word)?.meanings }

    func fetchExample(for word: String) async throws -> String? {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let sentence = local.example(for: normalized) { return sentence }
        let entries = try await onlineEntries(normalized)
        return entries.compactMap { example(in: $0) }.first
    }

    private func example(in entry: DictionaryResponse) -> String? {
        entry.meanings.flatMap(\.definitions).compactMap(\.example)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func onlineEntries(_ word: String) async throws -> [DictionaryResponse] {
        if let cached = cachedEntries[word] { return cached }

        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word)") else {
            throw DictionaryServiceError.invalidWord
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw DictionaryServiceError.invalidResponse }
        if http.statusCode == 404 { throw DictionaryServiceError.wordNotFound }
        guard http.statusCode == 200 else { throw DictionaryServiceError.server(http.statusCode) }
        guard let result = try? JSONDecoder().decode([DictionaryResponse].self, from: data) else { throw DictionaryServiceError.invalidResponse }

        if cachedEntries.count >= 200 { cachedEntries.removeAll() }
        // Do not cache empty examples forever: a manual retry should make a new request.
        if result.contains(where: { example(in: $0) != nil }) { cachedEntries[word] = result }
        return result
    }

    private func translatedDefinition(for definition: String) async -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [URLQueryItem(name: "q", value: definition), URLQueryItem(name: "langpair", value: "en|zh-CN")]
        guard let url = components?.url,
              let (data, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 3)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let translation = try? JSONDecoder().decode(TranslationResponse.self, from: data),
              let text = translation.responseData?.translatedText,
              !text.isEmpty else { return "（暂无中文释义）" }
        return text
    }

}
