import Foundation

enum ExerciseMode: String, Codable, CaseIterable {
    case recognition, chineseSpelling, listeningSpelling, missingLetters
    var title: String {
        switch self {
        case .recognition: return "看词回忆释义"
        case .chineseSpelling: return "看中文拼英文"
        case .listeningSpelling: return "听音拼写"
        case .missingLetters: return "缺失字母填空"
        }
    }
}

struct SkillScore: Codable {
    var attempts = 0
    var correct = 0
    var streak = 0
    mutating func record(_ success: Bool) {
        attempts += 1
        correct += success ? 1 : 0
        streak = success ? streak + 1 : 0
    }
    var summary: String {
        attempts == 0 ? "尚未练习" : "\(correct)/\(attempts) 次通过 · 最近连续 \(streak) 次"
    }
}

struct WordExercise: Codable, Identifiable {
    var id = UUID()
    let mode: ExerciseMode
    var missingIndices: [Int] = []
    var submittedAnswer: String?
    var correct: Bool?
    var candidateLetters: [String]?

    init(mode: ExerciseMode, word: String, excluding previous: [Int] = []) {
        self.mode = mode
        if mode == .missingLetters {
            let letters = Array(word)
            let indices = letters.indices.filter { letters[$0].isASCII && letters[$0].isLetter }
            let count = min(3, indices.count / 2)
            let previousLetters = Set(previous.filter { letters.indices.contains($0) }.map { String(letters[$0]).lowercased() })
            let available = indices.filter { !previous.contains($0) }.shuffled()
            let fresh = available.filter { !previousLetters.contains(String(letters[$0]).lowercased()) }
            var seen = Set<String>()
            missingIndices = Array((fresh.isEmpty ? available : fresh).filter {
                seen.insert(String(letters[$0]).lowercased()).inserted
            }.prefix(count)).sorted()
            refreshCandidates(word: word)
        }
    }

    mutating func refreshCandidates(word: String) {
        let required = Set(expectedAnswer(for: word).lowercased().map(String.init))
        let distractors = Array("abcdefghijklmnopqrstuvwxyz").map(String.init).filter { !required.contains($0) }.shuffled()
        candidateLetters = (Array(required) + Array(distractors.prefix(max(0, 10 - required.count)))).shuffled()
    }

    func validMissingIndices(for word: String) -> Bool {
        let letters = Array(word)
        let count = letters.filter { $0.isASCII && $0.isLetter }.count
        guard !missingIndices.isEmpty, missingIndices.count <= min(3, count / 2),
              Set(missingIndices).count == missingIndices.count,
              missingIndices.allSatisfy({ letters.indices.contains($0) && letters[$0].isASCII && letters[$0].isLetter }) else { return false }
        return Set(missingIndices.map { String(letters[$0]).lowercased() }).count == missingIndices.count
    }

    func prompt(for word: String) -> String {
        Array(word).enumerated().map { missingIndices.contains($0.offset) ? "＿" : String($0.element) }.joined(separator: " ")
    }

    func expectedAnswer(for word: String) -> String {
        guard mode == .missingLetters else { return word }
        return Array(word).enumerated().filter { missingIndices.contains($0.offset) }.map { String($0.element) }.joined()
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }

    func accepts(_ answer: String, word: String) -> Bool {
        Self.normalized(answer) == Self.normalized(expectedAnswer(for: word))
    }
}

struct DailyStudyPlan: Codable {
    var newWordLimit = 10
    var reviewLimit = 30
}

struct DailyStudyProgress: Codable {
    var day: Date
    var newWordIDs: Set<UUID> = []
    var reviewIDs: Set<UUID> = []
    var allIDs: Set<UUID> { newWordIDs.union(reviewIDs) }
}

enum WordStatusFilter: String, CaseIterable, Identifiable {
    case all = "全部状态", new = "新词", unfamiliar = "不认识", familiar = "熟悉"
    var id: String { rawValue }
}

enum WordSortOrder: String, CaseIterable, Identifiable {
    case newest = "最新添加", alphabet = "字母 A–Z", review = "复习时间"
    var id: String { rawValue }
}

struct ReviewRecord: Codable {
    var stage = 0
    var dueAt = Date.distantPast
    var lastReviewedAt: Date?
    var reviewCount: Int?
    var recognitionScore: SkillScore?
    var spellingScore: SkillScore?
    var exerciseScores: [String: SkillScore]?
    var usedExerciseModes: [ExerciseMode]?
    var lastExerciseMode: ExerciseMode?
    var pendingExercise: WordExercise?
    var lastMissingIndices: [Int]?

    mutating func prepareExercise(word: String) -> WordExercise {
        if var pending = pendingExercise {
            if pending.mode == .missingLetters && pending.correct == nil {
                if word.filter({ $0.isASCII && $0.isLetter }).count < 2 {
                    pending = WordExercise(mode: .chineseSpelling, word: word)
                } else if !pending.validMissingIndices(for: word) {
                    pending = WordExercise(mode: .missingLetters, word: word, excluding: lastMissingIndices ?? [])
                } else {
                    pending.missingIndices.sort()
                    let choices = pending.candidateLetters ?? []
                    let required = Set(pending.expectedAnswer(for: word).lowercased().map(String.init))
                    if choices.count != 10 || Set(choices).count != 10 || !required.isSubset(of: Set(choices)) {
                        pending.refreshCandidates(word: word)
                    }
                }
                pendingExercise = pending
            }
            return pending
        }
        var eligible = ExerciseMode.allCases
        if word.filter({ $0.isASCII && $0.isLetter }).count < 2 { eligible.removeAll { $0 == .missingLetters } }
        var used = usedExerciseModes ?? []
        var candidates = eligible.filter { !used.contains($0) }
        if candidates.isEmpty {
            used = []
            candidates = eligible.filter { $0 != lastExerciseMode }
        }
        let mode = candidates.randomElement() ?? .recognition
        usedExerciseModes = used
        let exercise = WordExercise(mode: mode, word: word, excluding: lastMissingIndices ?? [])
        pendingExercise = exercise
        return exercise
    }

    mutating func finishExercise(_ exercise: WordExercise, success: Bool) {
        if exercise.mode == .missingLetters { lastMissingIndices = exercise.missingIndices }
        var score = exerciseScores?[exercise.mode.rawValue] ?? SkillScore()
        score.record(success)
        var scores = exerciseScores ?? [:]
        scores[exercise.mode.rawValue] = score
        exerciseScores = scores
        if exercise.mode == .recognition {
            var recognition = recognitionScore ?? SkillScore()
            recognition.record(success)
            recognitionScore = recognition
        } else {
            var spelling = spellingScore ?? SkillScore()
            spelling.record(success)
            spellingScore = spelling
        }
        usedExerciseModes = (usedExerciseModes ?? []) + [exercise.mode]
        lastExerciseMode = exercise.mode
        pendingExercise = nil
    }

    // Practical spaced repetition intervals, not a personalized memory prediction.
    static let intervals = [1, 2, 4, 7, 15, 30, 60]

    mutating func answer(remembered: Bool, now: Date, calendar: Calendar = .current) {
        lastReviewedAt = now
        reviewCount = (reviewCount ?? 0) + 1
        if remembered {
            let days = Self.intervals[min(stage, Self.intervals.count - 1)]
            dueAt = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(Double(days) * 86400)
            stage = min(stage + 1, Self.intervals.count - 1)
        } else {
            stage = 0
            dueAt = now.addingTimeInterval(10 * 60)
        }
    }
}
