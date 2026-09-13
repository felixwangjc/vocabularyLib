import Foundation

private final class MockDictionaryProtocol: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests += 1
        if request.url!.path.hasSuffix("/timeoutword") {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        if request.url!.path.hasSuffix("/offlineword") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let json: String
        let status = request.url!.path.hasSuffix("/limitedword") ? 429 : (request.url!.path.hasSuffix("/missingword") ? 404 : 200)
        if request.url!.host == "api.mymemory.translated.net" {
            json = #"{"responseData":{"translatedText":"测试释义"}}"#
        } else if request.url!.path.hasSuffix("/malformedword") {
            json = "invalid JSON"
        } else if request.url!.path.hasSuffix("/emptyword") {
            json = #"[{"word":"emptyword","meanings":[{"definitions":[{"definition":"No example."}]}]}]"#
        } else {
            json = #"[{"word":"test","meanings":[{"partOfSpeech":"noun","definitions":[{"definition":"A test definition."},{"definition":"A second noun sense."}]}]},{"word":"test","meanings":[{"partOfSpeech":"verb","definitions":[{"definition":"Another meaning.","example":"This is a real example."}]},{"partOfSpeech":"noun","definitions":[{"definition":"A test definition."},{"definition":"A third noun sense."}]}]}]"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct VerifyDictionaryService {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDictionaryProtocol.self]
        let service = DictionaryService(local: LocalDictionary(databaseURL: URL(fileURLWithPath: CommandLine.arguments[1])), session: URLSession(configuration: configuration))
        let entry = try await service.lookup(" Apple ")
        precondition(entry.word == "apple" && entry.needsExample)
        precondition(MockDictionaryProtocol.requests == 0, "Local hits must not call the network")
        let example = try await service.fetchExample(for: entry.word)
        precondition(example == "This is a real example.")
        let cached = try await service.fetchExample(for: entry.word)
        precondition(cached == example && MockDictionaryProtocol.requests == 1)
        let fallback = try await service.lookup("qwertytestword")
        precondition(fallback.groupedMeanings.map(\.partOfSpeech) == ["noun", "verb"])
        precondition(fallback.groupedMeanings[0].englishDefinitions.count == 3, "Keep all senses across entries, deduplicated")
        precondition(fallback.groupedMeanings[1].englishDefinitions == ["Another meaning."])
        precondition(fallback.groupedMeanings.allSatisfy { $0.chineseDefinitions == ["测试释义"] })
        let laterExample = try await service.fetchExample(for: "qwertytestword")
        precondition(laterExample == "This is a real example.", "Must inspect all returned entries")
        do {
            _ = try await service.lookup("offlineword")
            fatalError("Offline misses must report failure")
        } catch is URLError {}
        do {
            _ = try await service.lookup("a sentence")
            fatalError("Invalid input must be rejected")
        } catch DictionaryServiceError.invalidWord {}
        let offline = DictionaryService(local: LocalDictionary(databaseURL: URL(fileURLWithPath: CommandLine.arguments[1]), examplesURL: URL(fileURLWithPath: CommandLine.arguments[2])), session: URLSession(configuration: configuration))
        let before = MockDictionaryProtocol.requests
        let sentence = try await offline.fetchExample(for: " Firmly ")
        precondition(sentence == "we firmly believed it")
        precondition(MockDictionaryProtocol.requests == before, "Local examples must not use the network")
        for word in ["timeoutword", "limitedword", "missingword", "malformedword"] {
            do {
                _ = try await service.fetchExample(for: word)
                fatalError("Expected diagnostic for \(word)")
            } catch {
                switch word {
                case "timeoutword": precondition((error as? URLError)?.code == .timedOut)
                case "limitedword": guard case DictionaryServiceError.server(429) = error else { fatalError("Wrong status") }
                case "missingword": guard case DictionaryServiceError.wordNotFound = error else { fatalError("Wrong missing-word error") }
                default: guard case DictionaryServiceError.invalidResponse = error else { fatalError("Wrong parse error") }
                }
            }
        }
        let priorEmpty = MockDictionaryProtocol.requests
        for _ in 0..<2 {
            let empty = try await service.fetchExample(for: "emptyword")
            precondition(empty == nil)
        }
        precondition(MockDictionaryProtocol.requests == priorEmpty + 2, "Missing examples must remain retryable")
        print("Service checks passed: offline-first, example extraction/cache, online fallback, failure and validation.")
    }
}
