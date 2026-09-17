import SwiftUI
import UserNotifications

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
