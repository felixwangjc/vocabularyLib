import XCTest
@testable import VocabularyLib

final class BadgeProgressTests: XCTestCase {
    func testCatalogContainsRewardAndAlphabetBadges() {
        XCTAssertEqual(BadgeCatalog.rewardBadges.count, 30)
        XCTAssertEqual(BadgeCatalog.alphabetBadges.count, 52)
        XCTAssertEqual(BadgeCatalog.all.count, 82)
        XCTAssertEqual(Set(BadgeCatalog.all.map(\.id)).count, 82)
        XCTAssertEqual(Set(BadgeCatalog.all.map(\.assetName)).count, 82)
        XCTAssertEqual(BadgeCatalog.rewardBadges.map(\.cost), BadgeCatalog.rewardBadges.map(\.cost).sorted())
    }

    func testAlphabetBadgesUnlockAtFiftyAndOneHundredWords() {
        let words = (0..<49).map { "a\($0)" }
            + (0..<50).map { "B\($0)" }
            + (0..<100).map { "c\($0)" }
            + ["  123", "中文"]
        let earned = BadgeCatalog.automaticallyEarnedBadgeIDs(for: words)

        XCTAssertFalse(earned.contains("letter_lower_a"))
        XCTAssertTrue(earned.contains("letter_lower_b"))
        XCTAssertFalse(earned.contains("letter_upper_b"))
        XCTAssertTrue(earned.contains("letter_lower_c"))
        XCTAssertTrue(earned.contains("letter_upper_c"))
        XCTAssertEqual(BadgeCatalog.initialCounts(for: words)["c"], 100)
    }

    func testAlphabetBadgesCannotBeRedeemedWithPoints() {
        var progress = BadgeProgress(points: 10_000)
        let badge = BadgeCatalog.alphabetBadges[0]
        XCTAssertFalse(progress.redeem(badge))
        XCTAssertFalse(progress.ownedBadgeIDs.contains(badge.id))
    }

    func testDailyCheckInOnlyAwardsOnceAndBuildsStreak() {
        var progress = BadgeProgress()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(progress.checkIn(at: firstDay, calendar: calendar).awardedPoints, 5)
        XCTAssertEqual(progress.checkIn(at: firstDay.addingTimeInterval(60), calendar: calendar).awardedPoints, 0)
        XCTAssertEqual(progress.checkIn(at: firstDay.addingTimeInterval(86_400), calendar: calendar).awardedPoints, 5)
        XCTAssertEqual(progress.currentStreak, 2)
        XCTAssertEqual(progress.points, 10)
    }

    func testMilestonesReplaceDailyRewardAndPersistDates() throws {
        var progress = BadgeProgress()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var expected = 0
        for day in 1...730 {
            let date = start.addingTimeInterval(Double(day - 1) * 86400)
            let reward = [7: 10, 30: 20, 100: 40, 365: 80, 730: 160][day] ?? 5
            XCTAssertEqual(progress.checkIn(at: date, calendar: calendar).awardedPoints, reward)
            XCTAssertEqual(progress.checkIn(at: date, calendar: calendar).awardedPoints, 0)
            expected += reward
        }
        XCTAssertEqual(progress.points, expected)
        XCTAssertEqual(progress.checkInDates?.count, 730)
        let restored = try JSONDecoder().decode(BadgeProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(restored, progress)
        XCTAssertEqual(progress.checkIn(at: start, calendar: calendar).awardedPoints, 0)
    }

    func testLegacyHistoryDoesNotInventDatesOrChangePoints() throws {
        let json = """
        {"points":123,"totalPointsEarned":200,"currentStreak":6,"longestStreak":6,"totalCheckInDays":6,"lastCheckInAt":100000,"lastCheckInPoints":45,"ownedBadgeIDs":[]}
        """
        var progress = try JSONDecoder().decode(BadgeProgress.self, from: Data(json.utf8))
        let last = try XCTUnwrap(progress.lastCheckInAt)
        XCTAssertEqual(progress.checkIn(at: last).awardedPoints, 0)
        XCTAssertEqual(progress.points, 123)
        XCTAssertEqual(progress.checkInDates, [last])
        XCTAssertEqual(progress.checkIn(at: last.addingTimeInterval(86400 * 3)).awardedPoints, 10)
        XCTAssertEqual(progress.currentStreak, 1)
        XCTAssertEqual(progress.totalCheckInDays, 7)
    }

    func testSwitchListeningDoesNotGradeAndSurvivesReload() throws {
        var record = ReviewRecord()
        let pending = WordExercise(mode: .listeningSpelling, word: "apple")
        record.pendingExercise = pending
        record.usedExerciseModes = [.recognition, .chineseSpelling]
        let replacement = try XCTUnwrap(record.replaceListeningExercise(word: "apple", id: pending.id))
        XCTAssertEqual(replacement.mode, .missingLetters)
        XCTAssertNil(record.reviewCount)
        XCTAssertNil(record.spellingScore)
        XCTAssertNil(record.recognitionScore)
        XCTAssertNil(record.lastReviewedAt)
        var restored = try JSONDecoder().decode(ReviewRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.prepareExercise(word: "apple").id, replacement.id)
        XCTAssertNil(record.replaceListeningExercise(word: "apple", id: pending.id))
        var graded = pending
        graded.correct = false
        record.pendingExercise = graded
        XCTAssertNil(record.replaceListeningExercise(word: "apple", id: pending.id))
    }

    func testMissedDayResetsStreakAndRedeemingSpendsPoints() {
        var progress = BadgeProgress(points: 100)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)
        _ = progress.checkIn(at: firstDay, calendar: calendar)
        _ = progress.checkIn(at: firstDay.addingTimeInterval(86_400 * 2), calendar: calendar)

        XCTAssertEqual(progress.currentStreak, 1)
        let badge = BadgeCatalog.all[1]
        XCTAssertTrue(progress.redeem(badge))
        XCTAssertFalse(progress.redeem(badge))
        XCTAssertTrue(progress.ownedBadgeIDs.contains(badge.id))
    }
}
