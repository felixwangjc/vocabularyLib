import SwiftUI
import CryptoKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct DailySlang: Codable, Identifiable {
    struct Slang: Codable {
        let id: String
        let phrase: String
        let meaningZh: String
        let usageNoteZh: String
    }
    struct Scenario: Codable {
        struct Line: Codable, Identifiable {
            let id: String
            let speaker: String
            let en: String
            let zh: String
            let isTarget: Bool
        }
        struct Illustration: Codable {
            let url: URL
            let altZh: String
        }
        let titleZh: String
        let lines: [Line]
        let illustration: Illustration
    }
    let schemaVersion: Int
    let dailyId: String
    let nextRefreshAt: String
    let slang: Slang
    let scenario: Scenario
    var id: String { dailyId }
}

struct SlangPresentationHistory: Codable {
    struct Entry: Codable {
        let day: String
        let slangID: String
        let phrase: String
    }
    var entries: [Entry] = []
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func normalized(_ phrase: String) -> String {
        phrase.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    func hasShown(on now: Date) -> Bool { entries.contains { $0.day == Self.day(now) } }
    func canShow(_ content: DailySlang, at now: Date) -> Bool {
        let today = Self.day(now)
        guard content.schemaVersion == 1, content.dailyId == today,
              let expires = ISO8601DateFormatter().date(from: content.nextRefreshAt), expires > now,
              !content.slang.phrase.isEmpty, !content.scenario.lines.isEmpty,
              content.scenario.illustration.url.scheme == "https", !hasShown(on: now) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let cutoff = Self.day(calendar.date(byAdding: .day, value: -60, to: now)!)
        return !entries.contains {
            $0.day >= cutoff && $0.day <= today &&
            ($0.slangID == content.slang.id || $0.phrase == Self.normalized(content.slang.phrase))
        }
    }
    func choose(from cache: [DailySlang], at now: Date) -> DailySlang? {
        guard !hasShown(on: now) else { return nil }
        let last = entries.last
        let eligible = cache.filter {
            $0.slang.id != last?.slangID && Self.normalized($0.slang.phrase) != last?.phrase
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let cutoff = Self.day(calendar.date(byAdding: .day, value: -60, to: now)!)
        let fresh = eligible.filter { item in
            !entries.contains { $0.day >= cutoff && ($0.slangID == item.slang.id || $0.phrase == Self.normalized(item.slang.phrase)) }
        }
        return (fresh.isEmpty ? eligible : fresh).randomElement()
    }

    mutating func record(_ content: DailySlang, presentedAt: Date? = nil) {
        let day = presentedAt.map(Self.day) ?? content.dailyId
        guard !entries.contains(where: { $0.day == day }) else { return }
        entries.append(Entry(day: day, slangID: content.slang.id, phrase: Self.normalized(content.slang.phrase)))
        entries.sort { $0.day < $1.day }
        // At most one presentation per day; retain enough entries for 60 days,
        // even when the app is used infrequently.
        entries = Array(entries.suffix(120))
    }
}

@MainActor
final class DailySlangStore: ObservableObject {
    @Published private(set) var content: DailySlang?
    @Published private(set) var owner: UUID?
    private var loading = false
    private let defaults: UserDefaults
    private let historyKey = "vocabulary.dailySlang.history.v1"
    private let cacheKey = "vocabulary.dailySlang.cache.v1"
    private var history: SlangPresentationHistory
    private var cache: [DailySlang] = []
    private let poolKey = "vocabulary.dailySlang.pool.v2"

    init(defaults: UserDefaults = .standard) {
        #if DEBUG
        let defaults = ProcessInfo.processInfo.environment["REVIEW_UI_TEST_ID"]
            .flatMap { UUID(uuidString: $0).map { UserDefaults(suiteName: "com.vocabularylib.slang-tests.\($0.uuidString)")! } } ?? defaults
        #endif
        self.defaults = defaults
        history = defaults.data(forKey: historyKey).flatMap { try? JSONDecoder().decode(SlangPresentationHistory.self, from: $0) } ?? SlangPresentationHistory()
        cache = defaults.data(forKey: poolKey).flatMap { try? JSONDecoder().decode([DailySlang].self, from: $0) } ?? []
        if cache.isEmpty, let data = defaults.data(forKey: cacheKey), let old = try? JSONDecoder().decode(DailySlang.self, from: data) { cache = [old] }
    }

    func openIfNeeded(owner id: UUID) async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["REVIEW_UI_TEST_ID"] != nil {
            if let payload = ProcessInfo.processInfo.environment["SLANG_UI_TEST_PAYLOAD"],
               let daily = try? JSONDecoder().decode(DailySlang.self, from: Data(payload.utf8)),
               history.canShow(daily, at: .now) {
                owner = id
                content = daily
            }
            return
        }
        #endif
        guard !loading, content == nil, !history.hasShown(on: .now) else { return }
        loading = true
        defer { loading = false }
        // Present immediately from disk. Never replace an already visible card
        // with the network result; downloaded items are for the next opening.
        if let cached = history.choose(from: cache, at: .now) {
            owner = id
            content = cached
        }
        do {
            var url = URLComponents(string: "https://daily-slang-api-590936940507.asia-southeast1.run.app/v1/slang/batch")!
            url.queryItems = [URLQueryItem(name: "exclude", value: content?.slang.id ?? history.entries.last?.slangID ?? ""),
                              URLQueryItem(name: "known", value: cache.map { $0.slang.id }.joined(separator: ","))]
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let received = try JSONDecoder().decode([DailySlang].self, from: data)
            for item in received where item.schemaVersion == 1 && !item.slang.phrase.isEmpty && !item.scenario.lines.isEmpty && item.scenario.illustration.url.scheme == "https" {
                cache.removeAll { $0.slang.id == item.slang.id }
                cache.append(item)
            }
            cache = Array(cache.suffix(120))
            defaults.set(try? JSONEncoder().encode(cache), forKey: poolKey)
            if !Task.isCancelled, content == nil, let next = history.choose(from: cache, at: .now) {
                owner = id
                content = next
            }
            // Persist illustrations as well as text so offline playback is complete.
            for item in received { await SlangImageCache.download(item.scenario.illustration.url) }
        } catch { /* A network failure never removes the local content pool. */ }
    }

    func didPresent(_ content: DailySlang) {
        history.record(content, presentedAt: .now)
        defaults.set(try? JSONEncoder().encode(history), forKey: historyKey)
    }
    func dismiss() { content = nil; owner = nil }
}

struct DailySlangSplash: ViewModifier {
    @ObservedObject var store: DailySlangStore
    @Environment(\.scenePhase) private var phase
    @State private var owner = UUID()
    private var isPresented: Binding<Bool> {
        Binding(get: { store.content != nil && store.owner == owner }, set: { if !$0 { store.dismiss() } })
    }
    @ViewBuilder private var splash: some View {
        if let daily = store.content {
            DailySlangCard(content: daily, close: store.dismiss)
                .onAppear { store.didPresent(daily) }
        }
    }
    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .fullScreenCover(isPresented: isPresented) { splash }
            #else
            .disabled(isPresented.wrappedValue)
            .overlay {
                if isPresented.wrappedValue { splash }
            }
            #endif
            .task(id: phase) {
                if phase == .active { await store.openIfNeeded(owner: owner) }
            }
    }
}

private struct DailySlangCard: View {
    let content: DailySlang
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var ink: Color { scheme == .dark ? Color(white: 0.96) : Color(white: 0.10) }
    private var secondaryInk: Color { scheme == .dark ? Color(white: 0.80) : Color(white: 0.30) }
    private var canvas: Color { scheme == .dark ? Color(white: 0.07) : Color(red: 1, green: 0.98, blue: 0.94) }
    private var accent: Color { scheme == .dark ? Color(red: 1, green: 0.68, blue: 0.35) : Color(red: 0.64, green: 0.23, blue: 0.01) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("每日俚语", systemImage: "sparkles").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).accessibilityLabel("关闭每日俚语")
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(content.slang.phrase).font(.largeTitle.bold()).foregroundStyle(accent)
                    Text(content.slang.meaningZh).font(.title3)
                    CachedSlangImage(url: content.scenario.illustration.url, alt: content.scenario.illustration.altZh)
                        .frame(maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 18))
                    Text(content.scenario.titleZh).font(.headline)
                    ForEach(content.scenario.lines) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(line.speaker)  ·  \(line.en)").fontWeight(line.isTarget ? .semibold : .regular)
                            Text(line.zh).font(.subheadline).foregroundStyle(secondaryInk)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(line.isTarget ? (scheme == .dark ? Color(red: 0.24, green: 0.16, blue: 0.09) : Color(red: 1, green: 0.91, blue: 0.79)) : (scheme == .dark ? Color(white: 0.14) : .white), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Text(content.slang.usageNoteZh).font(.subheadline).foregroundStyle(secondaryInk)
                }.padding(.horizontal, 24).padding(.bottom, 20).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
            Button(action: close) {
                Text("开始今天的学习").foregroundStyle(scheme == .dark ? Color.black : Color.white)
            }.buttonStyle(.borderedProminent).controlSize(.large).padding(16)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(ink).tint(accent)
            .background(canvas.ignoresSafeArea()).accessibilityAddTraits(.isModal)
    }
}

enum SlangImageCache {
    static func file(_ url: URL) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SlangImages", isDirectory: true)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key)
    }
    static func image(_ url: URL) -> Image? {
        guard let data = try? Data(contentsOf: file(url)) else { return nil }
        #if os(iOS)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #else
        return NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }
    static func download(_ url: URL) async {
        guard url.scheme == "https", image(url) == nil else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 5 * 1024 * 1024 else { return }
            #if os(iOS)
            guard UIImage(data: data) != nil else { return }
            #else
            guard NSImage(data: data) != nil else { return }
            #endif
            let destination = file(url)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch { }
    }
}

private struct CachedSlangImage: View {
    let url: URL
    let alt: String
    @State private var image: Image?
    @State private var loading = true
    @State private var attempt = 0
    var body: some View {
        Group {
            if let displayed = image ?? SlangImageCache.image(url) {
                displayed.resizable().scaledToFit().accessibilityLabel(alt)
            } else if loading {
                ProgressView("加载情景插图…").frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Button("重试加载图片") { attempt += 1 }.frame(maxWidth: .infinity, minHeight: 180)
            }
        }.task(id: attempt) {
            image = SlangImageCache.image(url)
            loading = image == nil
            if image == nil { await SlangImageCache.download(url); image = SlangImageCache.image(url) }
            loading = false
        }
    }
}
