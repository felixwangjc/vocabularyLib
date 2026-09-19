import SwiftUI
import UserNotifications

/// The badge catalog is bounded (82 items). Measure its entire height instead
/// of revising lazy estimates underneath the check-in header while scrolling.
struct BadgeCatalogLayout: Layout {
    var minimumColumnWidth: CGFloat
    var spacing: CGFloat

    private func measurements(width: CGFloat, subviews: Subviews) -> (columns: Int, cellWidth: CGFloat, heights: [CGFloat]) {
        let columns = max(1, Int((width + spacing) / (minimumColumnWidth + spacing)))
        let cellWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var heights: [CGFloat] = []
        for index in subviews.indices {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            let row = index / columns
            if row == heights.count { heights.append(height) }
            else { heights[row] = max(heights[row], height) }
        }
        return (columns, cellWidth, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimumColumnWidth
        let metrics = measurements(width: width, subviews: subviews)
        return CGSize(width: width, height: metrics.heights.reduce(0, +) + CGFloat(max(0, metrics.heights.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = measurements(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for index in subviews.indices {
            let column = index % metrics.columns
            let row = index / metrics.columns
            if column == 0 && row > 0 { y += metrics.heights[row - 1] + spacing }
            subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (metrics.cellWidth + spacing), y: y),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(width: metrics.cellWidth, height: metrics.heights[row]))
        }
    }
}

struct CheckInLifecycle: ViewModifier {
    @EnvironmentObject private var store: VocabularyStore
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                store.checkInIfNeeded()
                // Also handles an app left open across midnight.
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { return }
            }
        }
    }
}

struct CheckInWall: View {
    @EnvironmentObject private var store: VocabularyStore
    private let calendar = Calendar.current
    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (-29...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("打卡墙 · 最近 30 天", systemImage: "calendar.badge.checkmark").font(.title3.bold())
            Text("累计 \(store.badgeProgress.totalCheckInDays) 天 · 连续 \(store.badgeProgress.currentStreak) 天 · 最长连续 \(store.badgeProgress.longestStreak) 天")
                .font(.subheadline).foregroundStyle(.secondary)
            // Only 30 cells: measure all five rows eagerly. A lazy calendar and
            // a sibling lazy badge grid can change their height as they scroll
            // offscreen, moving the header and causing a layout feedback loop.
            let dates = days
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            if index < dates.count {
                                dayCell(dates[index])
                                    .accessibilityIdentifier("checkInDay-\(index)")
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            Text("✓ 已打卡　○ 未打卡　⊖ 历史未记录；边框标记今天")
                .font(.caption).foregroundStyle(.secondary)
            Text("每天 5 分；累计第 7 / 30 / 100 / 365 天分别获得 10 / 20 / 40 / 80 分，之后每满 365 天奖励再翻倍。里程碑积分替代当天的 5 分。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
    }

    private func dayCell(_ day: Date) -> some View {
        let checked = store.badgeProgress.didCheckIn(on: day)
        let unknown = !checked && day < calendar.startOfDay(for: store.badgeProgress.historyStartedAt ?? .now)
        return VStack(spacing: 5) {
            Text(day, format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.caption2)
            Image(systemName: checked ? "checkmark.circle.fill" : unknown ? "minus.circle" : "circle")
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 9)
        .background(checked ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(calendar.isDateInToday(day) ? Color.accentColor : .clear) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted))，\(checked ? "已打卡" : unknown ? "未记录" : "未打卡")")
    }
}

struct OCRSourceFields: View {
    @Binding var book: String
    @Binding var page: String
    var body: some View {
        DisclosureGroup("阅读来源（可选）") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("书名 / 文章标题", text: $book).textFieldStyle(.roundedBorder)
                TextField("页码，例如 12 或 12–13", text: $page).textFieldStyle(.roundedBorder)
                Text("应用于接下来加入的单词。已存在的词会追加原句，不重复收词；添加后可编辑笔记和对应词义。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }.font(.subheadline).padding(.vertical, 8)
    }
}

struct ReadingContextSection: View {
    @EnvironmentObject private var store: VocabularyStore
    let entryID: UUID
    var editable = true
    @State private var editing: ReadingContext?
    private var entry: WordEntry? { store.entries.first { $0.id == entryID } }
    var body: some View {
        if let entry, let contexts = entry.readingContexts, !contexts.isEmpty {
            DisclosureGroup("阅读语境（\(contexts.count)）") {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(contexts) { context in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(context.sentence).font(.body).textSelection(.enabled)
                            Text([context.bookTitle.isEmpty ? "图片识词" : context.bookTitle,
                                  context.page.isEmpty ? "" : "第 \(context.page) 页"].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            if let meaning = context.selectedMeaning, !meaning.isEmpty {
                                Label(meaning, systemImage: "bookmark.fill").font(.subheadline).foregroundStyle(.tint)
                            }
                            if !context.note.isEmpty { Text("笔记：\(context.note)").font(.subheadline) }
                            if editable {
                                Button("编辑来源、笔记与词义") { editing = context }
                                    .font(.subheadline).accessibilityIdentifier("editReadingContext")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(.top, 12)
            }
            .sheet(item: $editing) { context in
                ReadingContextEditor(entry: entry, context: context)
            }
        }
    }
}

private struct ReadingContextEditor: View {
    @EnvironmentObject private var store: VocabularyStore
    @Environment(\.dismiss) private var dismiss
    let entry: WordEntry
    @State private var draft: ReadingContext
    @State private var saveFailed = false

    init(entry: WordEntry, context: ReadingContext) {
        self.entry = entry
        _draft = State(initialValue: context)
    }

    private var senses: [String] {
        var values = entry.groupedMeanings.flatMap { meaning in
            (meaning.chineseDefinitions.isEmpty ? meaning.englishDefinitions : meaning.chineseDefinitions)
                .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ";；")) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                .map { "\(meaning.title)：\($0)" }
        }
        if let selected = draft.selectedMeaning, !values.contains(selected) { values.append(selected) }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Text("阅读记录 · \(entry.word)").font(.headline).lineLimit(1)
                Spacer()
                Button("保存") {
                    if store.saveReadingContext(draft, for: entry.id) { dismiss() }
                    else { saveFailed = true }
                }.disabled(draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding()
            Form {
                Section("原句 / OCR 片段") {
                    TextEditor(text: $draft.sentence).frame(minHeight: 90).accessibilityIdentifier("sourceSentence")
                    Text("请对照原文修正识别错误；被裁剪的内容可能不是完整句子。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("阅读来源") {
                    TextField("书名 / 文章标题", text: $draft.bookTitle).accessibilityIdentifier("sourceBookTitle")
                    TextField("页码", text: $draft.page).accessibilityIdentifier("sourcePage")
                }
                Section("这次阅读中的词义") {
                    Picker("对应词义", selection: $draft.selectedMeaning) {
                        Text("尚未标记").tag(nil as String?)
                        ForEach(senses, id: \.self) { Text($0).tag(Optional($0)) }
                    }.pickerStyle(.menu)
                    Text("选择具体释义，不会改变单词的其他词义或其他阅读记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("个人笔记") {
                    TextEditor(text: $draft.note).frame(minHeight: 90).accessibilityIdentifier("sourceNote")
                }
                if saveFailed { Text("保存失败，单词可能已被删除。") }
            }.formStyle(.grouped)
        }.frame(minWidth: 300, minHeight: 480)
    }
}

struct WordLibraryControls: View {
    @EnvironmentObject private var store: VocabularyStore
    @Binding var query: String
    @Binding var status: WordStatusFilter
    @Binding var tag: String?
    @Binding var sort: WordSortOrder
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索英文、中文释义或标签", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                    .accessibilityIdentifier("wordSearch")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("清空搜索")
                }
            }
            .padding(12).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            ViewThatFits(in: .horizontal) {
                HStack { filters }
                VStack(alignment: .leading) { filters }
            }
            if !query.isEmpty || status != .all || tag != nil || sort != .newest {
                Button("重置筛选与排序") { query = ""; status = .all; tag = nil; sort = .newest }
                    .font(.caption)
            }
        }
        .onChange(of: store.allTags) { _, tags in
            if let tag, !tags.contains(tag) { self.tag = nil }
        }
        .onDisappear { searchFocused = false }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { searchFocused = false }
            }
            #endif
        }
    }

    @ViewBuilder private var filters: some View {
        Picker("状态", selection: $status) {
            ForEach(WordStatusFilter.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).labelsHidden().fixedSize().accessibilityLabel("状态")
        Picker("标签", selection: $tag) {
            Text("全部标签").tag(nil as String?)
            ForEach(store.allTags, id: \.self) { Text($0).tag(Optional($0)) }
        }.pickerStyle(.menu).labelsHidden().fixedSize().accessibilityLabel("标签")
        Picker("排序", selection: $sort) {
            ForEach(WordSortOrder.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).labelsHidden().fixedSize().accessibilityLabel("排序")
    }
}

struct WordTagsEditor: View {
    @EnvironmentObject private var store: VocabularyStore
    let entryID: UUID
    @State private var editing = false
    @State private var draft = ""
    private var tags: [String] { store.entries.first { $0.id == entryID }?.tags ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("分类标签", systemImage: "tag").font(.subheadline.bold())
                Spacer()
                Button(editing ? "取消" : "编辑") {
                    draft = tags.joined(separator: "，")
                    editing.toggle()
                }
            }
            if editing {
                TextField("例如：工作，阅读，考试", text: $draft).textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Text("多个标签用逗号分隔；清空后保存可移除标签。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存标签", action: save).buttonStyle(.borderedProminent)
            } else {
                Text(tags.isEmpty ? "未分类 · 可添加自定义标签" : tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() { store.setTags(draft, for: entryID); editing = false }
}

struct StudyPlanSettings: View {
    @EnvironmentObject private var store: VocabularyStore
    var body: some View {
        Section("每日学习计划") {
            Stepper("每天新词：\(store.studyPlan.newWordLimit) 个", value: Binding(
                get: { store.studyPlan.newWordLimit },
                set: { store.updateStudyPlan(newWords: $0, reviews: store.studyPlan.reviewLimit) }
            ), in: 0...100).accessibilityIdentifier("dailyNewWordLimit")
            Stepper("每天旧词：\(store.studyPlan.reviewLimit) 个", value: Binding(
                get: { store.studyPlan.reviewLimit },
                set: { store.updateStudyPlan(newWords: store.studyPlan.newWordLimit, reviews: $0) }
            ), in: 0...300).accessibilityIdentifier("dailyReviewLimit")
            Text("优先复习到期旧词，再学习新词。数量为每日上限，不足时按实际词数安排；设为 0 可暂停该类任务。修改立即生效，已学记录保留。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("进度自动保存，可随时退出后继续。忘记的词在 10 分钟后重练，不重复占用名额；每日按本地日期重新安排。")
                .font(.footnote).foregroundStyle(.secondary)
            StudyReminderSettings()
        }
    }
}

private struct StudyReminderSettings: View {
    @AppStorage("study.reminder.enabled") private var enabled = false
    @AppStorage("study.reminder.hour") private var hour = 20
    @AppStorage("study.reminder.minute") private var minute = 0
    @State private var busy = false
    @State private var message: String?
    private let identifier = "vocabulary.daily-study"
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }, set: { date in
            hour = Calendar.current.component(.hour, from: date)
            minute = Calendar.current.component(.minute, from: date)
            if enabled { Task { await configure(true) } }
        })
    }

    var body: some View {
        Toggle("每日学习提醒", isOn: Binding(get: { enabled }, set: { requested in
            Task { await configure(requested) }
        })).disabled(busy)
        if enabled {
            DatePicker("提醒时间", selection: time, displayedComponents: .hourAndMinute).disabled(busy)
            Text("每天按所选时间提醒，完成当天任务后仍会提醒。可随时关闭。")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }

    @MainActor private func configure(_ requested: Bool) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        let center = UNUserNotificationCenter.current()
        if !requested {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            enabled = false
            return
        }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                enabled = false
                message = "通知权限未开启，请在系统设置的通知中允许 Vocabulary Lib 发送通知。"
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "今天的单词，复习一下吧"
            content.body = "打开每日复习，继续你的新词学习与到期复习。"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            enabled = true
        } catch {
            message = "提醒设置失败：\(error.localizedDescription)"
        }
    }
}

struct StudyPlanSummary: View {
    @EnvironmentObject private var store: VocabularyStore
    let now: Date
    @State private var showSettings = false

    var body: some View {
        let progress = store.dailyProgress(at: now)
        let queue = store.plannedWords(at: now)
        let target = progress.allIDs.count + queue.filter { !progress.allIDs.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日学习计划").font(.headline)
                Spacer()
                Button("调整计划") { showSettings = true }
            }
            Text("新词已学 \(progress.newWordIDs.count) / 上限 \(store.studyPlan.newWordLimit) · 旧词已复习 \(progress.reviewIDs.count) / 上限 \(store.studyPlan.reviewLimit)")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            ProgressView("今日首轮进度 \(progress.allIDs.count) / \(target)",
                         value: Double(progress.allIDs.count), total: Double(max(1, target)))
            Text("当前可学 \(queue.count) 词 · 已学按不同单词计数，不代表已掌握")
                .font(.caption).foregroundStyle(.secondary)
            if let retry = store.nextRetry(at: now) {
                Text("有单词待重练：\(retry.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showSettings) {
            VStack {
                HStack { Text("学习计划").font(.headline); Spacer(); Button("完成") { showSettings = false } }.padding()
                Form { StudyPlanSettings() }.formStyle(.grouped)
            }
            .frame(minWidth: 300, minHeight: 360)
        }
    }
}
