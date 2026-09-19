import SwiftUI

struct BadgeView: View {
    @EnvironmentObject private var store: VocabularyStore
    @State private var message: BadgeMessage?
    @State private var filter: BadgeFilter = .all

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                progressHeader
                CheckInWall()
                Picker("筛选徽章", selection: $filter) {
                    ForEach(BadgeFilter.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
                BadgeCatalogLayout(minimumColumnWidth: 155, spacing: 14) {
                    ForEach(visibleBadges) { badge in
                        badgeCard(badge)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("徽章馆")
        .learningScreenBackground()
        .alert(item: $message) { value in
            Alert(title: Text(value.title), message: Text(value.detail), dismissButton: .default(Text("知道了")))
        }
    }

    private var visibleBadges: [BadgeDefinition] {
        switch filter {
        case .all: BadgeCatalog.all
        case .alphabet: BadgeCatalog.alphabetBadges
        case .available: BadgeCatalog.rewardBadges.filter { !store.owns($0) && store.badgeProgress.points >= $0.cost }
        case .owned: BadgeCatalog.all.filter(store.owns)
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日打卡完成").font(.title2.bold())
                    Text("每天首次打开获得 5 分，累计打卡解锁翻倍里程碑奖励。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title).foregroundStyle(AppTheme.accent)
            }
            HStack(spacing: 10) {
                stat("可用积分", "\(store.badgeProgress.points)", "seal.fill")
                stat("连续天数", "\(store.badgeProgress.currentStreak)", "flame.fill")
                stat("累计打卡", "\(store.badgeProgress.totalCheckInDays)", "calendar")
            }
            Label("今天已获得 \(store.badgeProgress.lastCheckInPoints) 积分", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
        }
        .padding(22).studyCard()
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Label(value, systemImage: icon).font(.headline).foregroundStyle(AppTheme.accent)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity)
        .background(AppTheme.peach.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }

    private func badgeCard(_ badge: BadgeDefinition) -> some View {
        let owned = store.owns(badge)
        let affordable = store.badgeProgress.points >= badge.cost
        let highlighted = owned || (!badge.isAlphabetBadge && affordable)
        return VStack(spacing: 10) {
            Image(badge.assetName)
                .resizable().scaledToFit().frame(height: 104)
                .saturation(highlighted ? 1 : 0.25)
                .opacity(highlighted ? 1 : 0.58)
                .accessibilityHidden(true)
            Text(badge.name).font(.headline).multilineTextAlignment(.center)
            Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
            if owned {
                Label("已收藏", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold()).foregroundStyle(.green)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else if case let .points(cost) = badge.unlockRequirement {
                ProgressView(value: min(Double(store.badgeProgress.points) / Double(badge.cost), 1))
                    .tint(AppTheme.accent)
                Button { redeem(badge) } label: {
                    Label("\(cost) 积分", systemImage: affordable ? "sparkles" : "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .disabled(!affordable)
            } else if case let .initialWordCount(_, required) = badge.unlockRequirement {
                let count = store.initialWordCount(for: badge)
                ProgressView(value: min(Double(count) / Double(required), 1))
                    .tint(AppTheme.accent)
                Label("\(count) / \(required) 个单词", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pastel(cardTintSeed(for: badge)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.08)) }
    }

    private func cardTintSeed(for badge: BadgeDefinition) -> Int {
        badge.cost > 0 ? badge.cost : badge.assetName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }

    private func redeem(_ badge: BadgeDefinition) {
        if store.redeem(badge) {
            message = BadgeMessage(title: "兑换成功", detail: "“\(badge.name)”已经加入你的徽章收藏。")
        } else {
            message = BadgeMessage(title: "积分不足", detail: "继续每天使用 App，就能积攒更多积分。")
        }
    }
}

private enum BadgeFilter: String, CaseIterable, Identifiable {
    case all, alphabet, available, owned
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部 \(BadgeCatalog.all.count)"
        case .alphabet: "字母"
        case .available: "可兑换"
        case .owned: "已收藏"
        }
    }
}

private struct BadgeMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}
