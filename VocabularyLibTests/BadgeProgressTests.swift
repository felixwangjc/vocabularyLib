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

        XCTAssertEqual(progress.checkIn(at: firstDay, calendar: calendar).awardedPoints, 20)
        XCTAssertEqual(progress.checkIn(at: firstDay.addingTimeInterval(60), calendar: calendar).awardedPoints, 0)
        XCTAssertEqual(progress.checkIn(at: firstDay.addingTimeInterval(86_400), calendar: calendar).awardedPoints, 25)
        XCTAssertEqual(progress.currentStreak, 2)
        XCTAssertEqual(progress.points, 45)
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
