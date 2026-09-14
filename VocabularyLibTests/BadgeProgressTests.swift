import XCTest
@testable import VocabularyLib

final class BadgeProgressTests: XCTestCase {
    func testCatalogContainsThirtyUniqueBadges() {
        XCTAssertEqual(BadgeCatalog.all.count, 30)
        XCTAssertEqual(Set(BadgeCatalog.all.map(\.id)).count, 30)
        XCTAssertEqual(Set(BadgeCatalog.all.map(\.assetName)).count, 30)
        XCTAssertEqual(BadgeCatalog.all.map(\.cost), BadgeCatalog.all.map(\.cost).sorted())
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
