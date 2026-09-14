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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        badgeProgress = defaults.data(forKey: badgeProgressKey)
            .flatMap { try? JSONDecoder().decode(BadgeProgress.self, from: $0) } ?? BadgeProgress()
        load()
        if let data = defaults.data(forKey: reviewKey),
           let records = try? JSONDecoder().decode([String: ReviewRecord].self, from: data) {
            reviews = records
        }
        let outcome = checkInIfNeeded()
        latestCheckInOutcome = outcome.didCheckIn ? outcome : nil
    }

    func dueWords(at now: Date) -> [WordEntry] {
        entries.filter { (reviews[$0.id.uuidString]?.dueAt ?? .distantPast) <= now }
            .sorted { (reviews[$0.id.uuidString]?.dueAt ?? $0.createdAt) < (reviews[$1.id.uuidString]?.dueAt ?? $1.createdAt) }
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

    func review(_ entry: WordEntry, remembered: Bool, now: Date = .now) {
        guard entries.contains(where: { $0.id == entry.id }) else { return }
        var record = reviews[entry.id.uuidString] ?? ReviewRecord()
        record.answer(remembered: remembered, now: now)
        reviews[entry.id.uuidString] = record
        if let data = try? JSONEncoder().encode(reviews) {
            defaults.set(data, forKey: reviewKey)
        }
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
        entries.remove(atOffsets: offsets)
        save()
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
}
