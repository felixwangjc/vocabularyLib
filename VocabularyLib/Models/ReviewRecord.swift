import Foundation

struct ReviewRecord: Codable {
    var stage = 0
    var dueAt = Date.distantPast
    var lastReviewedAt: Date?
    var reviewCount: Int?

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
