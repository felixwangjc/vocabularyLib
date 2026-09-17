import Foundation
import SwiftUI

@MainActor
final class VocabularyStore: ObservableObject {
    @Published private(set) var entries: [WordEntry] = []
    @Published var isLoading = false
    @Published private(set) var reviews: [String: ReviewRecord] = [:]
    private let reviewKey = "vocabulary.reviews.v1"
    @Published private(set) var badgeProgress: BadgeProgress
    @Published private(set) var latestCheckInOutcome: DailyCheckInOutcome?
    private let badgeProgressKey = "vocabulary.badges.v1"

    private let storageKey = "vocabulary.entries.v1"
    private let dictionary = DictionaryService()
    private let defaults: UserDefaults
    @Published private(set) var loadingExamples: Set<UUID> = []
    @Published private(set) var exampleMessages: [UUID: String] = [:]
    @Published private(set) var studyPlan: DailyStudyPlan
    @Published private var studyProgress: DailyStudyProgress
    private let planKey = "vocabulary.studyPlan.v1"
    private let progressKey = "vocabulary.studyProgress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        studyPlan = defaults.data(forKey: planKey)
            .flatMap { try? JSONDecoder().decode(DailyStudyPlan.self, from: $0) } ?? DailyStudyPlan()
        studyProgress = defaults.data(forKey: progressKey)
            .flatMap { try? JSONDecoder().decode(DailyStudyProgress.self, from: $0) }
            ?? DailyStudyProgress(day: .distantPast)
        badgeProgress = defaults.data(forKey: badgeProgressKey)
            .flatMap { try? JSONDecoder().decode(BadgeProgress.self, from: $0) } ?? BadgeProgress()
        load()
        unlockAlphabetBadgesIfNeeded()
        if let data = defaults.data(forKey: reviewKey),
           let records = try? JSONDecoder().decode([String: ReviewRecord].self, from: data) {
            reviews = records
        }
        let outcome = checkInIfNeeded()
        latestCheckInOutcome = outcome.didCheckIn ? outcome : nil
    }

    func dueWords(at now: Date) -> [WordEntry] {
        entries.filter { (reviews[$0.id.uuidString]?.dueAt ?? .distantPast) <= now }
            .sorted {
                let lhs = reviews[$0.id.uuidString]?.dueAt ?? .distantPast
                let rhs = reviews[$1.id.uuidString]?.dueAt ?? .distantPast
                if lhs != rhs { return lhs < rhs }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func upgradeLegacyMeanings() async {
        // Only old entries lack this field. Look up the full local entry off the main actor;
        // preserve IDs, examples, dates, and all review history.
        let legacy = entries.filter { $0.meanings == nil }
        guard !legacy.isEmpty else { return }
        defer { save() }
        for entry in legacy {
            guard !Task.isCancelled else { return }
            let meanings = await dictionary.localMeanings(for: entry.word) ?? entry.groupedMeanings
            guard let index = entries.firstIndex(where: { $0.id == entry.id }), entries[index].meanings == nil else { continue }
            entries[index].meanings = meanings
        }
    }

    func reviewedToday(at now: Date) -> Int {
        entries.filter {
            guard let date = reviews[$0.id.uuidString]?.lastReviewedAt else { return false }
            return Calendar.current.isDate(date, inSameDayAs: now)
        }.count
    }

    func review(_ entry: WordEntry, remembered: Bool, now: Date = .now, exercise: WordExercise? = nil) {
        guard entries.contains(where: { $0.id == entry.id }) else { return }
        studyProgress = dailyProgress(at: now)
        if !studyProgress.allIDs.contains(entry.id) {
            if reviews[entry.id.uuidString]?.lastReviewedAt == nil {
                studyProgress.newWordIDs.insert(entry.id)
            } else {
                studyProgress.reviewIDs.insert(entry.id)
            }
        }
        if let data = try? JSONEncoder().encode(studyProgress) { defaults.set(data, forKey: progressKey) }
        var record = reviews[entry.id.uuidString] ?? ReviewRecord()
        if let exercise { record.finishExercise(exercise, success: remembered) }
        record.answer(remembered: remembered, now: now)
        reviews[entry.id.uuidString] = record
        if let data = try? JSONEncoder().encode(reviews) {
            defaults.set(data, forKey: reviewKey)
        }
    }

    func exercise(for entry: WordEntry) -> WordExercise {
        var record = reviews[entry.id.uuidString] ?? ReviewRecord()
        let exercise = record.prepareExercise(word: entry.word)
        reviews[entry.id.uuidString] = record
        persistReviews()
        return exercise
    }

    func gradeExercise(for entry: WordEntry, id: UUID, answer: String) -> WordExercise? {
        guard var record = reviews[entry.id.uuidString], var exercise = record.pendingExercise,
              exercise.id == id, exercise.mode != .recognition else { return nil }
        if exercise.correct == nil {
            exercise.submittedAnswer = answer
            exercise.correct = exercise.accepts(answer, word: entry.word)
            record.pendingExercise = exercise
            reviews[entry.id.uuidString] = record
            persistReviews()
        }
        return exercise
    }

    func completeExercise(for entry: WordEntry, id: UUID, recognition: Bool? = nil, now: Date = .now) {
        guard let exercise = reviews[entry.id.uuidString]?.pendingExercise, exercise.id == id,
              let result = exercise.mode == .recognition ? recognition : exercise.correct else { return }
        review(entry, remembered: result, now: now, exercise: exercise)
    }

    private func persistReviews() {
        if let data = try? JSONEncoder().encode(reviews) { defaults.set(data, forKey: reviewKey) }
    }

    @discardableResult
    func checkInIfNeeded(at now: Date = .now) -> DailyCheckInOutcome {
        let outcome = badgeProgress.checkIn(at: now)
        if outcome.didCheckIn { saveBadgeProgress() }
        return outcome
    }

    func redeem(_ badge: BadgeDefinition) -> Bool {
        guard badgeProgress.redeem(badge) else { return false }
        saveBadgeProgress()
        return true
    }

    func owns(_ badge: BadgeDefinition) -> Bool {
        badgeProgress.ownedBadgeIDs.contains(badge.id)
    }

    func initialWordCount(for badge: BadgeDefinition) -> Int {
        guard case let .initialWordCount(letter, _) = badge.unlockRequirement else { return 0 }
        return BadgeCatalog.initialCounts(for: entries.map(\.word))[letter, default: 0]
    }

    func contains(_ word: String) -> Bool {
        entries.contains { $0.word.caseInsensitiveCompare(word.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }

    @discardableResult
    func add(word: String) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }
        let entry = try await dictionary.lookup(word)
        guard !contains(entry.word) else { return false }
        entries.insert(entry, at: 0)
        save()
        unlockAlphabetBadgesIfNeeded()
        Task { await supplementExample(for: entry.id) }
        return true
    }

    func supplementExample(for id: UUID) async {
        guard let entry = entries.first(where: { $0.id == id }),
              entry.needsExample, !loadingExamples.contains(id) else { return }
        loadingExamples.insert(id)
        exampleMessages[id] = nil
        defer { loadingExamples.remove(id) }
        do {
            let example = try await dictionary.fetchExample(for: entry.word)
            // The user may delete or replace the entry while this request is running.
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            if let example {
                entries[index].example = example
                save()
            } else {
                exampleMessages[id] = "本地及在线词典暂无此词的例句"
            }
        } catch {
            guard entries.contains(where: { $0.id == id }) else { return }
            if let network = error as? URLError {
                exampleMessages[id] = network.code == .timedOut
                    ? "本地暂无例句，在线请求超时，请稍后重试"
                    : "本地暂无例句，无法连接例句服务，请检查网络后重试"
            } else if case DictionaryServiceError.wordNotFound = error {
                exampleMessages[id] = "本地暂无例句，在线词典未收录此词形"
            } else {
                exampleMessages[id] = error.localizedDescription
            }
        }
    }

    func delete(at offsets: IndexSet) {
        delete(ids: Set(offsets.map { entries[$0].id }))
    }

    func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        for id in ids { reviews[id.uuidString] = nil }
        if let data = try? JSONEncoder().encode(reviews) { defaults.set(data, forKey: reviewKey) }
        save()
    }

    var allTags: [String] {
        Set(entries.flatMap { $0.tags ?? [] }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @discardableResult
    func saveReadingContext(_ context: ReadingContext, for entryID: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              !context.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var contexts = entries[index].readingContexts ?? []
        if let existing = contexts.firstIndex(where: { $0.id == context.id }) {
            contexts[existing] = context
        } else if !contexts.contains(where: { $0.hasSameContent(as: context) }) {
            contexts.append(context)
        }
        entries[index].readingContexts = contexts
        save()
        return true
    }

    func setTags(_ text: String, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ",，、\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var tags: [String] = []
        for part in parts where !tags.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
            tags.append(part)
        }
        entries[index].tags = tags
        save()
    }

    func filteredWords(query: String, status: WordStatusFilter, tag: String?, sort: WordSortOrder) -> [WordEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let record = reviews[entry.id.uuidString]
            let isNew = record?.lastReviewedAt == nil
            let matchesStatus = status == .all || (status == .new && isNew)
                || (status == .unfamiliar && !isNew && record?.stage == 0)
                || (status == .familiar && !isNew && (record?.stage ?? 0) > 0)
            let text = ([entry.word, entry.chineseDefinition, entry.englishDefinition] + (entry.tags ?? [])).joined(separator: "\n")
            return matchesStatus && (tag == nil || (entry.tags ?? []).contains(tag!))
                && (search.isEmpty || text.localizedStandardContains(search))
        }.sorted { lhs, rhs in
            switch sort {
            case .newest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            case .alphabet:
                let order = lhs.word.localizedStandardCompare(rhs.word)
                if order != .orderedSame { return order == .orderedAscending }
            case .review:
                let a = reviews[lhs.id.uuidString]?.dueAt ?? .distantPast
                let b = reviews[rhs.id.uuidString]?.dueAt ?? .distantPast
                if a != b { return a < b }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func updateStudyPlan(newWords: Int, reviews: Int) {
        studyPlan.newWordLimit = min(100, max(0, newWords))
        studyPlan.reviewLimit = min(300, max(0, reviews))
        if let data = try? JSONEncoder().encode(studyPlan) { defaults.set(data, forKey: planKey) }
    }

    func dailyProgress(at now: Date) -> DailyStudyProgress {
        if Calendar.current.isDate(studyProgress.day, inSameDayAs: now) { return studyProgress }
        // Preserve work already done today when upgrading from the version without plans.
        let existing = Set(entries.filter {
            guard let date = reviews[$0.id.uuidString]?.lastReviewedAt else { return false }
            return Calendar.current.isDate(date, inSameDayAs: now)
        }.map(\.id))
        return DailyStudyProgress(day: Calendar.current.startOfDay(for: now), reviewIDs: existing)
    }

    func plannedWords(at now: Date) -> [WordEntry] {
        let progress = dailyProgress(at: now)
        let due = dueWords(at: now)
        let retries = due.filter { progress.allIDs.contains($0.id) }
        let old = due.filter { !progress.allIDs.contains($0.id) && reviews[$0.id.uuidString]?.lastReviewedAt != nil }
        let new = due.filter { !progress.allIDs.contains($0.id) && reviews[$0.id.uuidString]?.lastReviewedAt == nil }
        return retries + Array(old.prefix(max(0, studyPlan.reviewLimit - progress.reviewIDs.count)))
            + Array(new.prefix(max(0, studyPlan.newWordLimit - progress.newWordIDs.count)))
    }

    func nextRetry(at now: Date) -> Date? {
        let ids = dailyProgress(at: now).allIDs
        return entries.filter { ids.contains($0.id) }.compactMap {
            guard let record = reviews[$0.id.uuidString], record.stage == 0, record.dueAt > now else { return nil }
            return record.dueAt
        }.min()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([WordEntry].self, from: data) else { return }
        entries = saved.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func saveBadgeProgress() {
        guard let data = try? JSONEncoder().encode(badgeProgress) else { return }
        defaults.set(data, forKey: badgeProgressKey)
    }

    private func unlockAlphabetBadgesIfNeeded() {
        let earned = BadgeCatalog.automaticallyEarnedBadgeIDs(for: entries.map(\.word))
        let previous = badgeProgress.ownedBadgeIDs
        badgeProgress.ownedBadgeIDs.formUnion(earned)
        if badgeProgress.ownedBadgeIDs != previous { saveBadgeProgress() }
    }
}
