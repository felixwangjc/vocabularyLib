import XCTest
@testable import VocabularyLib

@MainActor
final class StudyPlanAndSearchTests: XCTestCase {
    func testLetterPuzzlesRespectLimitsAndAvoidPreviousPositions() async throws {
        for word in ["at", "cat", "apple", "banana", "aaaa", "Mississippi", "ice-cream", "don't", "understanding"] {
            var previous: [Int] = []
            for _ in 0..<40 {
                let exercise = WordExercise(mode: .missingLetters, word: word, excluding: previous)
                XCTAssertTrue(exercise.validMissingIndices(for: word), word)
                XCTAssertTrue(Set(previous).isDisjoint(with: exercise.missingIndices), word)
                let missing = exercise.expectedAnswer(for: word).lowercased().map(String.init)
                XCTAssertEqual(Set(missing).count, missing.count)
                XCTAssertLessThanOrEqual(missing.count, 3)
                XCTAssertLessThanOrEqual(missing.count * 2, word.filter(\.isLetter).count)
                let choices = try XCTUnwrap(exercise.candidateLetters)
                XCTAssertEqual(choices.count, 10)
                XCTAssertEqual(Set(choices).count, 10)
                XCTAssertTrue(Set(missing).isSubset(of: Set(choices)))
                previous = exercise.missingIndices
            }
        }
    }

    func testMissingLetterHistoryAndChoicesSurviveReload() async throws {
        var record = ReviewRecord()
        let first = WordExercise(mode: .missingLetters, word: "banana")
        record.finishExercise(first, success: true)
        record = try JSONDecoder().decode(ReviewRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(record.lastMissingIndices, first.missingIndices)
        record.usedExerciseModes = [.recognition, .chineseSpelling, .listeningSpelling]
        let next = record.prepareExercise(word: "banana")
        XCTAssertTrue(Set(first.missingIndices).isDisjoint(with: next.missingIndices))
        record = try JSONDecoder().decode(ReviewRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(record.prepareExercise(word: "banana").candidateLetters, next.candidateLetters)
        XCTAssertEqual(record.pendingExercise?.id, next.id)
    }

    func testLegacyMissingPuzzlesMigrateAndSingleLettersNeverGetBlanks() async throws {
        var record = ReviewRecord()
        var legacy = WordExercise(mode: .missingLetters, word: "mississippi")
        legacy.missingIndices = [0, 1, 2, 3, 4]
        legacy.candidateLetters = nil
        record.pendingExercise = legacy
        XCTAssertTrue(record.prepareExercise(word: "mississippi").validMissingIndices(for: "mississippi"))
        for word in ["a", "I"] {
            record = ReviewRecord()
            for _ in 0..<12 {
                let exercise = record.prepareExercise(word: word)
                XCTAssertNotEqual(exercise.mode, .missingLetters)
                record.finishExercise(exercise, success: true)
            }
        }
    }
    func testOCRSentenceJoinsWrappedLinesAndUsesExactOccurrence() async throws {
        let lines = [
            OCRTextLine(text: "The apple fell from", box: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.04)),
            OCRTextLine(text: "the tree. Another apple stayed.", box: CGRect(x: 0.1, y: 0.74, width: 0.6, height: 0.04))
        ]
        XCTAssertEqual(OCRSentenceExtractor.sentence(lines: lines, lineIndex: 0, wordRange: lines[0].text.range(of: "apple")!), "The apple fell from the tree.")
        XCTAssertEqual(OCRSentenceExtractor.sentence(lines: lines, lineIndex: 1, wordRange: lines[1].text.range(of: "apple")!), "Another apple stayed.")
    }

    func testOCRSentenceDoesNotJoinColumnsOrParagraphGaps() async throws {
        let first = OCRTextLine(text: "A small apple", box: CGRect(x: 0.05, y: 0.8, width: 0.3, height: 0.03))
        for next in [OCRTextLine(text: "unrelated text.", box: CGRect(x: 0.55, y: 0.76, width: 0.3, height: 0.03)),
                     OCRTextLine(text: "unrelated text.", box: CGRect(x: 0.05, y: 0.4, width: 0.3, height: 0.03))] {
            XCTAssertEqual(OCRSentenceExtractor.sentence(lines: [first, next], lineIndex: 0, wordRange: first.text.range(of: "apple")!), "A small apple")
        }
    }

    func testReadingContextsAppendEditDeduplicateAndPersist() async throws {
        let entry = word("apple")
        try withStore([entry]) { store, defaults in
            var first = ReadingContext(sentence: "I ate an apple.", bookTitle: "Reader", page: "12")
            XCTAssertTrue(store.saveReadingContext(first, for: entry.id))
            XCTAssertTrue(store.saveReadingContext(ReadingContext(sentence: first.sentence, bookTitle: "Reader", page: "12"), for: entry.id))
            XCTAssertEqual(store.entries.first?.readingContexts?.count, 1)
            first.note = "早餐遇到的词"
            first.selectedMeaning = "名词 · n.：苹果"
            XCTAssertTrue(store.saveReadingContext(first, for: entry.id))
            XCTAssertTrue(store.saveReadingContext(ReadingContext(sentence: "The apple is red.", page: "13"), for: entry.id))
            // Re-importing a source must neither duplicate it nor erase edited notes/senses.
            XCTAssertTrue(store.saveReadingContext(ReadingContext(sentence: first.sentence, bookTitle: "Reader", page: "12"), for: entry.id))
            let restored = VocabularyStore(defaults: defaults)
            XCTAssertEqual(restored.entries.first?.readingContexts?.count, 2)
            XCTAssertEqual(restored.entries.first?.readingContexts?.first?.selectedMeaning, first.selectedMeaning)
            XCTAssertEqual(restored.entries.first?.readingContexts?.first?.note, first.note)
            XCTAssertEqual(restored.entries.count, 1)
            XCTAssertFalse(restored.saveReadingContext(ReadingContext(sentence: "  "), for: entry.id))
            XCTAssertFalse(restored.saveReadingContext(first, for: UUID()))
        }
    }

    func testLegacyWordsDoNotRequireReadingContexts() async throws {
        let restored = try JSONDecoder().decode(WordEntry.self, from: JSONEncoder().encode(word("legacy")))
        XCTAssertNil(restored.readingContexts)
        XCTAssertEqual(restored.word, "legacy")
    }

    func testExerciseCyclesNeverRepeatWithinCycleOrAcrossBoundary() async throws {
        var record = ReviewRecord()
        var previous: ExerciseMode?
        for _ in 0..<30 {
            var cycle: Set<String> = []
            for _ in 0..<4 {
                let exercise = record.prepareExercise(word: "apple")
                XCTAssertNotEqual(exercise.mode, previous)
                XCTAssertTrue(cycle.insert(exercise.mode.rawValue).inserted)
                XCTAssertEqual(record.prepareExercise(word: "apple").id, exercise.id)
                record.finishExercise(exercise, success: true)
                previous = exercise.mode
                record = try JSONDecoder().decode(ReviewRecord.self, from: JSONEncoder().encode(record))
            }
            XCTAssertEqual(cycle.count, 4)
        }
        XCTAssertEqual(record.recognitionScore?.attempts, 30)
        XCTAssertEqual(record.spellingScore?.attempts, 90)
    }

    func testObjectiveGradingPersistenceAndExactlyOnceScoring() async throws {
        let entry = word("apple")
        var initial = ReviewRecord()
        initial.pendingExercise = WordExercise(mode: .chineseSpelling, word: entry.word)
        try withStore([entry], records: [entry.id.uuidString: initial]) { store, defaults in
            let exercise = store.exercise(for: entry)
            XCTAssertEqual(store.gradeExercise(for: entry, id: exercise.id, answer: " APPLE \n")?.correct, true)
            // Once revealed, subsequent edits cannot change the result.
            XCTAssertEqual(store.gradeExercise(for: entry, id: exercise.id, answer: "wrong")?.correct, true)
            let restored = VocabularyStore(defaults: defaults)
            XCTAssertEqual(restored.exercise(for: entry).id, exercise.id)
            XCTAssertEqual(restored.exercise(for: entry).correct, true)
            restored.completeExercise(for: entry, id: exercise.id, now: now)
            restored.completeExercise(for: entry, id: exercise.id, now: now)
            XCTAssertEqual(restored.reviews[entry.id.uuidString]?.reviewCount, 1)
            XCTAssertEqual(restored.reviews[entry.id.uuidString]?.spellingScore?.correct, 1)
            XCTAssertNil(restored.reviews[entry.id.uuidString]?.recognitionScore)
            XCTAssertEqual(restored.dailyProgress(at: now).newWordIDs.count, 1)
            XCTAssertNotEqual(restored.exercise(for: entry).mode, .chineseSpelling)
        }
    }

    func testFailedSpellingSchedulesRetryAndKeepsRecognitionSeparate() async throws {
        let entry = word("apple")
        var record = ReviewRecord()
        record.recognitionScore = SkillScore(attempts: 3, correct: 3, streak: 3)
        record.pendingExercise = WordExercise(mode: .listeningSpelling, word: entry.word)
        try withStore([entry], records: [entry.id.uuidString: record]) { store, _ in
            let exercise = store.exercise(for: entry)
            store.completeExercise(for: entry, id: exercise.id, now: now)
            XCTAssertNil(store.reviews[entry.id.uuidString]?.reviewCount)
            _ = store.gradeExercise(for: entry, id: exercise.id, answer: "aple")
            store.completeExercise(for: entry, id: exercise.id, now: now)
            let result = store.reviews[entry.id.uuidString]
            XCTAssertEqual(result?.dueAt, now.addingTimeInterval(600))
            XCTAssertEqual(result?.spellingScore?.attempts, 1)
            XCTAssertEqual(result?.spellingScore?.correct, 0)
            XCTAssertEqual(result?.recognitionScore?.correct, 3)
        }
    }

    func testMissingLettersAndInputNormalization() async throws {
        var exercise = WordExercise(mode: .missingLetters, word: "apple")
        exercise.missingIndices = [1, 3]
        XCTAssertEqual(exercise.expectedAnswer(for: "apple"), "pl")
        XCTAssertEqual(exercise.prompt(for: "apple"), "a ＿ p ＿ e")
        XCTAssertTrue(exercise.accepts(" PL ", word: "apple"))
        XCTAssertFalse(exercise.accepts("apple", word: "apple"))
        for word in ["ice-cream", "don't"] {
            let item = WordExercise(mode: .missingLetters, word: word)
            XCTAssertFalse(item.missingIndices.isEmpty)
            XCTAssertTrue(item.expectedAnswer(for: word).allSatisfy(\.isLetter))
        }
    }

    func testOldReviewRecordsDecodeWithoutInventingScores() async throws {
        let data = try JSONEncoder().encode(ReviewRecord(stage: 2, reviewCount: 5))
        let record = try JSONDecoder().decode(ReviewRecord.self, from: data)
        XCTAssertNil(record.recognitionScore)
        XCTAssertNil(record.spellingScore)
        XCTAssertEqual(record.reviewCount, 5)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func word(_ name: String, chinese: String = "释义") -> WordEntry {
        WordEntry(word: name, phonetic: "", chineseDefinition: chinese,
                  englishDefinition: "definition", example: "example", createdAt: now)
    }

    private func withStore(_ entries: [WordEntry], records: [String: ReviewRecord] = [:],
                           body: (VocabularyStore, UserDefaults) throws -> Void) throws {
        let suite = "StudyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(entries), forKey: "vocabulary.entries.v1")
        defaults.set(try JSONEncoder().encode(records), forKey: "vocabulary.reviews.v1")
        try body(VocabularyStore(defaults: defaults), defaults)
    }

    func testSearchTagsStatusAndSafeDelete() async throws {
        let apple = word("apple", chinese: "苹果")
        let book = word("book", chinese: "书本")
        let cat = word("cat")
        let records = [book.id.uuidString: ReviewRecord(stage: 1, lastReviewedAt: now),
                       cat.id.uuidString: ReviewRecord(stage: 0, lastReviewedAt: now)]
        try withStore([apple, book, cat], records: records) { store, defaults in
            store.setTags("阅读， Work,work， 阅读", for: apple.id)
            XCTAssertEqual(store.allTags.count, 2)
            XCTAssertEqual(store.filteredWords(query: " APPLE ", status: .all, tag: nil, sort: .newest).map(\.id), [apple.id])
            XCTAssertEqual(store.filteredWords(query: "苹果", status: .new, tag: "阅读", sort: .alphabet).map(\.id), [apple.id])
            XCTAssertEqual(store.filteredWords(query: "work", status: .all, tag: nil, sort: .alphabet).map(\.id), [apple.id])
            XCTAssertEqual(store.filteredWords(query: "", status: .familiar, tag: nil, sort: .alphabet).map(\.id), [book.id])
            XCTAssertEqual(store.filteredWords(query: "", status: .unfamiliar, tag: nil, sort: .alphabet).map(\.id), [cat.id])
            store.delete(ids: [book.id])
            XCTAssertEqual(Set(store.entries.map(\.id)), [apple.id, cat.id])
            XCTAssertNil(store.reviews[book.id.uuidString])
            let restored = VocabularyStore(defaults: defaults)
            XCTAssertEqual(restored.entries.first { $0.id == apple.id }?.tags, ["阅读", "Work"])
            store.setTags("", for: apple.id)
            XCTAssertTrue(store.allTags.isEmpty)
        }
    }

    func testLegacyWordWithoutTagsDecodes() async throws {
        let data = try JSONEncoder().encode(word("legacy"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "tags")
        let decoded = try JSONDecoder().decode(WordEntry.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.tags)
    }

    func testDailyLimitsOldWordsFirstAndResume() async throws {
        let old = word("old")
        let newer = word("newer")
        let extra = word("extra")
        let record = ReviewRecord(stage: 1, dueAt: now.addingTimeInterval(-100), lastReviewedAt: now.addingTimeInterval(-86400))
        try withStore([newer, extra, old], records: [old.id.uuidString: record]) { store, defaults in
            store.updateStudyPlan(newWords: 1, reviews: 1)
            XCTAssertEqual(store.plannedWords(at: now).count, 2)
            XCTAssertEqual(store.plannedWords(at: now).first?.id, old.id)
            store.review(old, remembered: true, now: now)
            let new = try XCTUnwrap(store.plannedWords(at: now).first)
            store.review(new, remembered: true, now: now)
            XCTAssertTrue(store.plannedWords(at: now).isEmpty)
            let restored = VocabularyStore(defaults: defaults)
            XCTAssertTrue(restored.plannedWords(at: now).isEmpty)
            XCTAssertEqual(restored.dailyProgress(at: now).newWordIDs.count, 1)
            XCTAssertEqual(restored.dailyProgress(at: now).reviewIDs.count, 1)
            XCTAssertEqual(restored.studyPlan.newWordLimit, 1)
        }
    }

    func testRetriesDoNotConsumeMoreQuota() async throws {
        let entry = word("retry")
        try withStore([entry, word("waiting")]) { store, _ in
            store.updateStudyPlan(newWords: 1, reviews: 0)
            store.review(entry, remembered: false, now: now)
            XCTAssertTrue(store.plannedWords(at: now).isEmpty)
            XCTAssertEqual(store.nextRetry(at: now), now.addingTimeInterval(600))
            XCTAssertEqual(store.plannedWords(at: now.addingTimeInterval(601)).map(\.id), [entry.id])
            store.review(entry, remembered: true, now: now.addingTimeInterval(601))
            XCTAssertEqual(store.dailyProgress(at: now).newWordIDs.count, 1)
            XCTAssertEqual(store.dailyProgress(at: now).reviewIDs.count, 0)
        }
    }

    func testDayRolloverAndLivePlanChanges() async throws {
        try withStore([word("one"), word("two"), word("three")]) { store, _ in
            store.updateStudyPlan(newWords: 1, reviews: 0)
            store.review(try XCTUnwrap(store.plannedWords(at: now).first), remembered: true, now: now)
            XCTAssertTrue(store.plannedWords(at: now).isEmpty)
            store.updateStudyPlan(newWords: 2, reviews: 0)
            XCTAssertEqual(store.plannedWords(at: now).count, 1)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
            XCTAssertEqual(store.dailyProgress(at: tomorrow).allIDs.count, 0)
            XCTAssertEqual(store.plannedWords(at: tomorrow).count, 2)
            store.updateStudyPlan(newWords: 0, reviews: 0)
            XCTAssertTrue(store.plannedWords(at: tomorrow).isEmpty)
        }
    }

    func testUpgradeCountsExistingReviewsToday() async throws {
        let entry = word("existing")
        let record = ReviewRecord(stage: 1, dueAt: now.addingTimeInterval(86400), lastReviewedAt: now)
        try withStore([entry], records: [entry.id.uuidString: record]) { store, _ in
            XCTAssertEqual(store.dailyProgress(at: now).reviewIDs, [entry.id])
        }
    }
}
