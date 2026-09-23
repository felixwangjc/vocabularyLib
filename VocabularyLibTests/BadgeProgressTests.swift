import XCTest
@testable import VocabularyLib

final class BadgeProgressTests: XCTestCase {
    func testDailySlangHistoryPersistsAndRejectsRecentRepeats() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-22T04:00:00Z")!
        let content = DailySlang(schemaVersion: 1, dailyId: "2026-09-22", nextRefreshAt: "2026-09-22T16:00:00Z",
                                 slang: .init(id: "valid", phrase: "Honestly, valid.", meaningZh: "合理", usageNoteZh: "口语"),
                                 scenario: .init(titleZh: "休息", lines: [.init(id: "a", speaker: "A", en: "Honestly, valid.", zh: "合理", isTarget: true)],
                                                 illustration: .init(url: URL(string: "https://example.com/a.jpg")!, altZh: "插图")))
        var history = SlangPresentationHistory()
        XCTAssertTrue(history.canShow(content, at: now))
        history.record(content)
        history.record(content)
        XCTAssertEqual(history.entries.count, 1)
        let saved = try JSONDecoder().decode(SlangPresentationHistory.self, from: JSONEncoder().encode(history))
        XCTAssertFalse(saved.canShow(content, at: now))
        XCTAssertTrue(saved.hasShown(on: now))
        XCTAssertFalse(saved.hasShown(on: now.addingTimeInterval(86400)))
        XCTAssertFalse(SlangPresentationHistory().canShow(content, at: now.addingTimeInterval(86400)))
        history.entries = [.init(day: "2026-07-24", slangID: "valid", phrase: "other")]
        XCTAssertFalse(history.canShow(content, at: now)) // exactly 60 days ago
        history.entries = [.init(day: "2026-07-23", slangID: "valid", phrase: "other")]
        XCTAssertTrue(history.canShow(content, at: now))
        history.entries = [.init(day: "2026-09-21", slangID: "renamed-id", phrase: SlangPresentationHistory.normalized("HONESTLY VALID!"))]
        XCTAssertFalse(history.canShow(content, at: now))
        XCTAssertNil(history.choose(from: [content], at: now)) // last phrase, even with a different ID
        let other = DailySlang(schemaVersion: 1, dailyId: "2026-09-01", nextRefreshAt: "2026-09-01T16:00:00Z",
                               slang: .init(id: "other", phrase: "You bet!", meaningZh: "当然", usageNoteZh: "口语"), scenario: content.scenario)
        XCTAssertEqual(history.choose(from: [content, other], at: now)?.slang.id, "other")
        history.entries.insert(.init(day: "2026-09-20", slangID: "other", phrase: "youbet"), at: 0)
        XCTAssertEqual(history.choose(from: [content, other], at: now)?.slang.id, "other") // offline fallback may repeat an older day
        history.record(other, presentedAt: now)
        XCTAssertTrue(history.hasShown(on: now)) // use display date, not cached server date
        XCTAssertNil(history.choose(from: [content, other], at: now))
        XCTAssertEqual(history.choose(from: [content, other], at: now.addingTimeInterval(86400))?.slang.id, "valid")
    }

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
        XCTAssertEqual(progress.checkIn(at: last.addingTimeInterval(86400 * 3)).awardedPoints, 5)
        XCTAssertEqual(progress.currentStreak, 1)
        XCTAssertEqual(progress.totalCheckInDays, 2)
    }

    func testFourRecordedDaysRepairEightDayLegacyCountersWithoutAwardingAgain() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12))!
        let dates = (0..<4).map { calendar.date(byAdding: .day, value: $0, to: first)! }
        var progress = BadgeProgress(points: 90, totalPointsEarned: 190, currentStreak: 8,
                                     longestStreak: 8, totalCheckInDays: 8,
                                     lastCheckInAt: dates[3], lastCheckInPoints: 5,
                                     ownedBadgeIDs: ["test-owned"], checkInDates: dates)
        XCTAssertEqual(progress.checkIn(at: dates[3], calendar: calendar).awardedPoints, 0)
        XCTAssertEqual(progress.totalCheckInDays, 4)
        XCTAssertEqual(progress.currentStreak, 4)
        XCTAssertEqual(progress.longestStreak, 4)
        XCTAssertEqual(progress.points, 90)
        XCTAssertEqual(progress.totalPointsEarned, 190)
        XCTAssertEqual(progress.ownedBadgeIDs, ["test-owned"])
        var restored = try JSONDecoder().decode(BadgeProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(restored.checkIn(at: dates[3], calendar: calendar).awardedPoints, 0)
        for day in 4...6 {
            let date = calendar.date(byAdding: .day, value: day, to: first)!
            XCTAssertEqual(restored.checkIn(at: date, calendar: calendar).awardedPoints, day == 6 ? 10 : 5)
        }
        XCTAssertEqual(restored.currentStreak, 7)
    }

    func testDuplicateDatesAndGapsUseDistinctCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let offsets = [0, 60, 86400, 3 * 86400, 4 * 86400, 5 * 86400]
        let dates = offsets.map { start.addingTimeInterval(Double($0)) }
        var progress = BadgeProgress(currentStreak: 99, longestStreak: 99, totalCheckInDays: 99,
                                     lastCheckInAt: dates.last, checkInDates: dates.reversed())
        _ = progress.checkIn(at: dates.last!, calendar: calendar)
        XCTAssertEqual(progress.totalCheckInDays, 5)
        XCTAssertEqual(progress.currentStreak, 3)
        XCTAssertEqual(progress.longestStreak, 3)
        _ = progress.checkIn(at: start.addingTimeInterval(8 * 86400), calendar: calendar)
        XCTAssertEqual(progress.currentStreak, 1)
        XCTAssertEqual(progress.longestStreak, 3)
        XCTAssertEqual(progress.totalCheckInDays, 6)
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
