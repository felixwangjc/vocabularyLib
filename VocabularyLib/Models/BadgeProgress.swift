import Foundation

struct BadgeDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let cost: Int
    let assetName: String
}

enum BadgeCatalog {
    static let all: [BadgeDefinition] = [
        .init(id: "first_step", name: "初芽", detail: "从今天开始，让学习生根。", cost: 20, assetName: "badge_first_step"),
        .init(id: "three_day_spark", name: "三日星火", detail: "小小坚持，已经点亮。", cost: 60, assetName: "badge_three_day_spark"),
        .init(id: "weekly_flame", name: "一周热焰", detail: "连续学习，热情正盛。", cost: 140, assetName: "badge_weekly_flame"),
        .init(id: "word_collector", name: "单词收藏家", detail: "把遇见的新词装进书架。", cost: 240, assetName: "badge_word_collector"),
        .init(id: "ocr_explorer", name: "识词探索者", detail: "从图片中发现语言线索。", cost: 360, assetName: "badge_ocr_explorer"),
        .init(id: "review_knight", name: "复习骑士", detail: "用复习守护每一段记忆。", cost: 500, assetName: "badge_review_knight"),
        .init(id: "pronunciation_star", name: "发音之星", detail: "让每个单词都被听见。", cost: 680, assetName: "badge_pronunciation_star"),
        .init(id: "vocabulary_scholar", name: "词汇学者", detail: "知识正在汇聚成册。", cost: 900, assetName: "badge_vocabulary_scholar"),
        .init(id: "streak_champion", name: "坚持冠军", detail: "稳定的节奏胜过一时冲刺。", cost: 1_150, assetName: "badge_streak_champion"),
        .init(id: "lexicon_master", name: "词典大师", detail: "抵达词汇旅程的闪耀里程碑。", cost: 1_500, assetName: "badge_lexicon_master"),
        .init(id: "ink_feather", name: "墨羽", detail: "让新词在笔尖留下痕迹。", cost: 180, assetName: "badge_ink_feather"),
        .init(id: "paper_horizon", name: "纸境远山", detail: "翻过一页，就看见更远的世界。", cost: 220, assetName: "badge_paper_horizon"),
        .init(id: "glass_heart", name: "琉璃词心", detail: "把闪光的词义收藏在心里。", cost: 260, assetName: "badge_glass_heart"),
        .init(id: "pixel_hero", name: "像素勇者", detail: "一格一格升级词汇能力。", cost: 300, assetName: "badge_pixel_hero"),
        .init(id: "neon_reader", name: "霓虹夜读", detail: "夜色再深，也有知识发光。", cost: 340, assetName: "badge_neon_reader"),
        .init(id: "woodland_rings", name: "年轮书语", detail: "日积月累，学习也有年轮。", cost: 380, assetName: "badge_woodland_rings"),
        .init(id: "clay_bookmark", name: "陶土书签", detail: "为今天的学习留个记号。", cost: 420, assetName: "badge_clay_bookmark"),
        .init(id: "enamel_compass", name: "词海罗盘", detail: "循着释义，找到正确方向。", cost: 460, assetName: "badge_enamel_compass"),
        .init(id: "watercolor_dawn", name: "水彩晨读", detail: "在清晨开启一页新知识。", cost: 500, assetName: "badge_watercolor_dawn"),
        .init(id: "origami_idea", name: "折纸灵感", detail: "让单词折叠成新的想象。", cost: 540, assetName: "badge_origami_idea"),
        .init(id: "steam_scholar", name: "蒸汽学者", detail: "用齿轮般的节奏持续精进。", cost: 580, assetName: "badge_steam_scholar"),
        .init(id: "cosmic_voyage", name: "星尘航海", detail: "从一页书驶向词汇宇宙。", cost: 620, assetName: "badge_cosmic_voyage"),
        .init(id: "crystal_memory", name: "冰晶记忆", detail: "让模糊的记忆重新清澈。", cost: 660, assetName: "badge_crystal_memory"),
        .init(id: "forest_guardian", name: "森林守护者", detail: "守护每一个刚学会的新词。", cost: 700, assetName: "badge_forest_guardian"),
        .init(id: "ocean_echo", name: "海洋回声", detail: "听见发音在记忆里回响。", cost: 740, assetName: "badge_ocean_echo"),
        .init(id: "postcard_rover", name: "词汇漫游家", detail: "用语言寄出通往世界的明信片。", cost: 780, assetName: "badge_postcard_rover"),
        .init(id: "geo_focus", name: "几何专注", detail: "用清晰结构整理复杂知识。", cost: 820, assetName: "badge_geo_focus"),
        .init(id: "future_mind", name: "未来思维", detail: "让学习能力持续迭代。", cost: 860, assetName: "badge_future_mind"),
        .init(id: "felt_owl", name: "毛毡智枭", detail: "温柔、耐心，也充满智慧。", cost: 900, assetName: "badge_felt_owl"),
        .init(id: "royal_archive", name: "皇家典藏", detail: "为珍贵词汇加冕并永久收藏。", cost: 1_000, assetName: "badge_royal_archive")
    ].sorted { $0.cost < $1.cost }
}

struct DailyCheckInOutcome: Equatable {
    let awardedPoints: Int
    let streak: Int
    var didCheckIn: Bool { awardedPoints > 0 }
}

struct BadgeProgress: Codable, Equatable {
    var points = 0
    var totalPointsEarned = 0
    var currentStreak = 0
    var longestStreak = 0
    var totalCheckInDays = 0
    var lastCheckInAt: Date?
    var lastCheckInPoints = 0
    var ownedBadgeIDs: Set<String> = []

    mutating func checkIn(at now: Date, calendar: Calendar = .current) -> DailyCheckInOutcome {
        if let lastCheckInAt, calendar.isDate(lastCheckInAt, inSameDayAs: now) {
            return DailyCheckInOutcome(awardedPoints: 0, streak: currentStreak)
        }

        if let lastCheckInAt {
            let lastDay = calendar.startOfDay(for: lastCheckInAt)
            let today = calendar.startOfDay(for: now)
            currentStreak = calendar.dateComponents([.day], from: lastDay, to: today).day == 1
                ? currentStreak + 1 : 1
        } else {
            currentStreak = 1
        }

        // 每日 20 分；连续签到每天多 5 分，第 7 天起封顶为 50 分。
        let reward = 20 + min(max(currentStreak - 1, 0) * 5, 30)
        points += reward
        totalPointsEarned += reward
        totalCheckInDays += 1
        longestStreak = max(longestStreak, currentStreak)
        lastCheckInAt = now
        lastCheckInPoints = reward
        return DailyCheckInOutcome(awardedPoints: reward, streak: currentStreak)
    }

    mutating func redeem(_ badge: BadgeDefinition) -> Bool {
        guard !ownedBadgeIDs.contains(badge.id), points >= badge.cost else { return false }
        points -= badge.cost
        ownedBadgeIDs.insert(badge.id)
        return true
    }
}
