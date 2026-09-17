import SwiftUI
import AVFoundation
import UIKit

enum WordAdditionResult {
    case added
    case duplicate
    case failed
}

struct ContentView: View {
    @EnvironmentObject private var store: VocabularyStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var word = ""
    @State private var selectedTab: AppTab = .addWord
    @State private var selectedEntry: WordEntry?
    @State private var alert: AppAlert?
    @State private var isShowingCamera = false
    @State private var showsImageImport = false
    @State private var pendingImage: UIImage?
    @State private var capturedImage: UIImage?
    @State private var showsReview = false
    @State private var showsSettings = false
    @State private var showsBadges = false
    @State private var dictionaryTerm: DictionaryTerm?
    @State private var isPastingImage = false
    @State private var showsImageMenu = false
    @State private var showsCheckInToast = true
    @State private var imageButtonFrame = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            Group {
            if isIPadLandscape(in: proxy.size) {
                HStack(spacing: 0) {
                    LandscapeWordSidebar(selectedEntry: $selectedEntry)
                        .frame(width: 310)
                    Divider()
                    NavigationStack {
                        InputWordView(word: $word, isLoading: store.isLoading, showsPageTitle: true, submit: addWord, toggleImageMenu: { setImageMenu(!showsImageMenu) }, reportButtonFrame: { imageButtonFrame = $0 })
                            .toolbar {
                                ToolbarItemGroup(placement: .topBarLeading) {
                                    Button("每日复习", systemImage: "brain.head.profile") { showsReview = true }
                                    Button("徽章馆", systemImage: "medal.fill") { showsBadges = true }
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("设置", systemImage: "gearshape") { showsSettings = true }
                                }
                            }
                    }
                }
            } else {
                tabs
            }
            }
        .onOpenURL { url in
            guard url.scheme == "vocabularylib" else { return }
            guard url.host == "review" || url.host == "add" else { return }
            selectedEntry = nil
            capturedImage = nil
            isShowingCamera = false
            showsSettings = false
            showsBadges = false
            showsReview = url.host == "review" && isIPadLandscape(in: proxy.size)
            selectedTab = url.host == "review" ? .review : .addWord
        }
        .onChange(of: proxy.size) { _, _ in setImageMenu(false) }
        }
        .overlay {
            GeometryReader { proxy in
                if showsImageMenu {
                    let origin = proxy.frame(in: .global).origin
                    let anchor = imageButtonFrame.isEmpty
                        ? CGPoint(x: proxy.size.width - 32, y: 22)
                        : CGPoint(x: imageButtonFrame.midX - origin.x, y: imageButtonFrame.midY - origin.y)
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { setImageMenu(false) }
                            .accessibilityHidden(true)
                        ImageRecognitionMenu(
                            camera: { setImageMenu(false); isShowingCamera = true },
                            paste: { setImageMenu(false); pasteImage() },
                            importImage: { setImageMenu(false); showsImageImport = true },
                            dismiss: { setImageMenu(false) }
                        )
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.05, anchor: .topTrailing).combined(with: .opacity))
                        .position(x: anchor.x - ImageRecognitionMenu.size / 2, y: anchor.y + ImageRecognitionMenu.size / 2)
                        // Keep the closing control exactly over the original toolbar icon.
                        Button { setImageMenu(false) } label: {
                            Image(systemName: "text.viewfinder")
                                .font(.body)
                                .frame(width: 44, height: 44)
                                .background(AppTheme.accentSoft, in: Circle())
                                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("收起图片识词菜单")
                        .position(anchor)
                    }
                    .transition(.opacity)
                }
            }
            .allowsHitTesting(showsImageMenu)
        }
        .onChange(of: selectedTab) { _, _ in setImageMenu(false) }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                ScrollView {
                    WordCard(entry: entry)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                    .background(AppTheme.canvas)
                    .navigationTitle(entry.word.capitalized)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selectedEntry = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsReview) {
            NavigationStack {
                ReviewView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showsReview = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView().toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsSettings = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showsBadges) {
            NavigationStack {
                BadgeView().toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsBadges = false }
                    }
                }
            }
        }
        .alert(item: $alert) { alert in
            if let word = alert.word {
                return Alert(title: Text(alert.title), message: Text(alert.message), primaryButton: .default(Text("查看系统词典")) { dictionaryTerm = DictionaryTerm(word: word) }, secondaryButton: .cancel(Text("取消")))
            }
            return Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("知道了")))
        }
        .sheet(item: $dictionaryTerm) { term in SystemDictionaryView(word: term.word) }
        .fullScreenCover(isPresented: $isShowingCamera, onDismiss: presentPendingImage) {
            CameraPicker { image in
                pendingImage = image
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsImageImport, onDismiss: presentPendingImage) {
            ImageImportView { image in pendingImage = image }
        }
        .overlay {
            if isPastingImage {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("正在读取剪贴板图片…")
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .sheet(isPresented: Binding(get: { capturedImage != nil }, set: { if !$0 { capturedImage = nil } })) {
            if let capturedImage {
                OCRReviewView(image: capturedImage, addWord: addRecognizedWord)
            }
        }
        .task { presentOCRTestFixtureIfNeeded() }
        .task {
            guard store.latestCheckInOutcome?.didCheckIn == true else { return }
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeOut(duration: 0.25)) { showsCheckInToast = false }
        }
        .overlay(alignment: .top) {
            if showsCheckInToast, let outcome = store.latestCheckInOutcome, outcome.didCheckIn {
                Label("今日打卡 +\(outcome.awardedPoints) 积分 · 连续 \(outcome.streak) 天", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold()).foregroundStyle(.green)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.green.opacity(0.22)) }
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityLabel("今日打卡获得 \(outcome.awardedPoints) 积分，连续 \(outcome.streak) 天")
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                InputWordView(word: $word, isLoading: store.isLoading, showsPageTitle: false, submit: addWord, toggleImageMenu: { setImageMenu(!showsImageMenu) }, reportButtonFrame: { imageButtonFrame = $0 })
                    .navigationTitle("输入单词")
            }
            .tabItem { Label("输入单词", systemImage: "text.cursor") }
            .tag(AppTab.addWord)

            NavigationStack {
                WordBookView(selectedEntry: $selectedEntry)
                    .navigationTitle("单词本")
            }
            .tabItem { Label("单词本", systemImage: "books.vertical") }
            .tag(AppTab.wordBook)
            NavigationStack { ReviewView() }
                .tabItem { Label("每日复习", systemImage: "brain.head.profile") }
                .tag(AppTab.review)
            NavigationStack { BadgeView() }
                .tabItem { Label("徽章", systemImage: "medal.fill") }
                .tag(AppTab.badges)
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(AppTheme.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(AppTheme.surface.opacity(0.96), for: .tabBar)
    }

    private func isIPadLandscape(in size: CGSize) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular
            && size.width > size.height
    }

    private func setImageMenu(_ visible: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.85)) {
            showsImageMenu = visible
        }
    }

    private func presentPendingImage() {
        guard let image = pendingImage else { return }
        pendingImage = nil
        capturedImage = image
    }

    private func pasteImage() {
        guard !isPastingImage else { return }
        guard let image = UIPasteboard.general.image else {
            alert = AppAlert(title: "无法粘贴", message: "剪贴板中没有可读取的图片，请先复制图片本身。")
            return
        }
        isPastingImage = true
        Task {
            defer { isPastingImage = false }
            do { capturedImage = try await ImportedImageLoader.prepare(image) }
            catch { alert = AppAlert(title: "无法粘贴图片", message: error.localizedDescription) }
        }
    }

    private func addWord() {
        let input = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        guard !store.contains(input) else {
            alert = AppAlert(title: "单词已存在", message: "“\(input)” 已经在你的单词本中。")
            return
        }
        Task {
            do {
                let didAdd = try await store.add(word: input)
                guard didAdd else {
                    alert = AppAlert(title: "单词已存在", message: "“\(input)” 已经在你的单词本中。")
                    return
                }
                word = ""
                selectedEntry = store.entries.first
            } catch {
                alert = AppAlert(title: "添加失败", message: error.localizedDescription, word: input)
            }
        }
    }

    private func addRecognizedWord(_ recognizedWord: String) async -> WordAdditionResult {
        guard !store.contains(recognizedWord) else {
            alert = AppAlert(title: "单词已存在", message: "“\(recognizedWord)” 已经在你的单词本中。")
            return .duplicate
        }
        do {
            let didAdd = try await store.add(word: recognizedWord)
            if !didAdd {
                alert = AppAlert(title: "单词已存在", message: "“\(recognizedWord)” 已经在你的单词本中。")
                return .duplicate
            }
            return .added
        } catch {
            alert = AppAlert(title: "添加失败", message: error.localizedDescription)
            return .failed
        }
    }

    private func presentOCRTestFixtureIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["OCR_CROP_UI_TEST"] == "1", capturedImage == nil else { return }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        capturedImage = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            NSString(string: "apple book cloud\nlearn every day")
                .draw(in: CGRect(x: 70, y: 180, width: 760, height: 300), withAttributes: attributes)
        }
        #endif
    }
}

private enum AppTab: Hashable {
    case settings
    case review
    case badges
    case addWord
    case wordBook
}

private struct InputWordView: View {
    @Binding var word: String
    let isLoading: Bool
    let showsPageTitle: Bool
    let submit: () -> Void
    let toggleImageMenu: () -> Void
    let reportButtonFrame: (CGRect) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if showsPageTitle {
                    Text("输入单词")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                }
                EntryComposer(word: $word, isLoading: isLoading, submit: submit)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("智能补充", systemImage: "sparkles")
                            .font(.title3.bold())
                        Spacer()
                        Text("添加后自动完成")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            FeaturePill(title: "中英文释义", icon: "character.book.closed", color: AppTheme.mint)
                            FeaturePill(title: "标准发音", icon: "speaker.wave.2", color: AppTheme.sky)
                            FeaturePill(title: "例句", icon: "text.quote", color: AppTheme.lemon)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                FeaturePill(title: "中英文释义", icon: "character.book.closed", color: AppTheme.mint)
                                FeaturePill(title: "标准发音", icon: "speaker.wave.2", color: AppTheme.sky)
                            }
                            FeaturePill(title: "例句", icon: "text.quote", color: AppTheme.lemon)
                        }
                    }
                }
                .padding(22)
                .studyCard()
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .learningScreenBackground()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ImageMenuButton { frame in
                    reportButtonFrame(frame)
                    toggleImageMenu()
                }
                .frame(width: 32, height: 32)
            }
        }
    }
}

private struct WordBookView: View {
    @EnvironmentObject private var store: VocabularyStore
    @Binding var selectedEntry: WordEntry?
    @State private var query = ""
    @State private var status: WordStatusFilter = .all
    @State private var tag: String?
    @State private var sort: WordSortOrder = .newest
    private var words: [WordEntry] { store.filteredWords(query: query, status: status, tag: tag, sort: sort) }

    var body: some View {
        List {
            WordLibraryControls(query: $query, status: $status, tag: $tag, sort: $sort)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section {
                if words.isEmpty {
                    ContentUnavailableView(store.entries.isEmpty ? "还没有单词" : "没有匹配的单词", systemImage: "magnifyingglass", description: Text("尝试添加单词，或调整搜索和筛选条件。"))
                        .listRowBackground(Color.clear)
                }
                ForEach(words) { entry in
                    Button { selectedEntry = entry } label: {
                        WordRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete { offsets in store.delete(ids: Set(offsets.map { words[$0].id })) }
            } header: {
                HStack {
                    Text("我的单词本").font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    Text("\(words.count) / \(store.entries.count) 词").foregroundStyle(AppTheme.accent)
                }
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .learningScreenBackground()
    }
}

private struct LandscapeWordSidebar: View {
    @EnvironmentObject private var store: VocabularyStore
    @Binding var selectedEntry: WordEntry?
    @State private var query = ""
    @State private var status: WordStatusFilter = .all
    @State private var tag: String?
    @State private var sort: WordSortOrder = .newest
    private var words: [WordEntry] { store.filteredWords(query: query, status: status, tag: tag, sort: sort) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("单词本")
                    .font(.system(.title, design: .rounded, weight: .black))
                Text("已记录 \(store.entries.count) 个单词")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 18)

            WordLibraryControls(query: $query, status: $status, tag: $tag, sort: $sort).padding(.horizontal, 16)

            if words.isEmpty {
                Spacer()
                ContentUnavailableView("没有匹配的单词", systemImage: "text.book.closed", description: Text("添加单词或调整筛选条件。"))
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                List(words) { entry in
                    Button { selectedEntry = entry } label: {
                        WordRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .learningScreenBackground()
    }
}

private struct EntryComposer: View {
    @Binding var word: String
    let isLoading: Bool
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Image(systemName: "character.book.closed.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.accent)
                    .padding(16)
                    .background(AppTheme.peach, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title2).foregroundStyle(AppTheme.accent.opacity(0.65))
            }
            Text("每一个新词，\n都是一点进步。")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            + Text(" ✦").foregroundStyle(AppTheme.accent)
            Text("本地查词，即刻收藏。例句会在联网时自动补充。")
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    wordField
                    addButton
                }
                VStack(spacing: 12) {
                    wordField
                    addButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if isLoading { ProgressView("正在查找释义…") }
        }
        .padding(24)
        .frame(maxWidth: 650)
        .studyCard()
        .padding(.horizontal, 20)
    }

    private var wordField: some View {
                TextField("例如：serendipity", text: $word)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.title3)
                    .padding(14)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
                    .onSubmit(submit)
    }

    private var addButton: some View {
        Button(action: submit) {
            Label("加入", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(isLoading)
    }
}

private struct FeaturePill: View {
    let title: String
    let icon: String
    let color: Color
    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(color, in: Capsule())
    }
}

private struct WordRow: View {
    @EnvironmentObject private var store: VocabularyStore
    @Environment(\.colorScheme) private var colorScheme
    let entry: WordEntry
    private var record: ReviewRecord? { store.reviews[entry.id.uuidString] }
    private var status: String { record?.lastReviewedAt == nil ? "新词" : (record!.stage == 0 ? "不认识" : "熟悉") }
    private var statusColor: Color {
        if record?.lastReviewedAt == nil {
            return colorScheme == .dark ? Color(red: 0.91, green: 0.76, blue: 0.40) : Color(red: 0.55, green: 0.39, blue: 0.05)
        }
        if record?.stage == 0 {
            return colorScheme == .dark ? Color(red: 0.94, green: 0.57, blue: 0.57) : Color(red: 0.72, green: 0.25, blue: 0.28)
        }
        return colorScheme == .dark ? Color(red: 0.48, green: 0.78, blue: 0.62) : Color(red: 0.18, green: 0.48, blue: 0.32)
    }
    private var rowColor: Color {
        let value = Int(entry.word.unicodeScalars.first?.value ?? 0)
        return AppTheme.pastel(value)
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(String(entry.word.prefix(1)).uppercased())
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40, height: 44)
                .background(AppTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.word).font(.headline)
                Text(entry.chineseDefinition).lineLimit(1).font(.subheadline).foregroundStyle(.secondary)
                if let tags = entry.tags, !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: "  ")).font(.caption).foregroundStyle(AppTheme.accent).lineLimit(2)
                }
                Text("\(status) · \(record?.reviewCount.map { "已复习 \($0) 次" } ?? (record?.lastReviewedAt == nil ? "已复习 0 次" : "历史次数未记录"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(rowColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(statusColor.opacity(colorScheme == .dark ? 0.34 : 0.22), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.045), radius: 8, y: 4)
        .contentShape(Rectangle())
    }
}

struct WordCard: View {
    @EnvironmentObject private var store: VocabularyStore
    let entry: WordEntry
    private var currentEntry: WordEntry { store.entries.first { $0.id == entry.id } ?? entry }
    @StateObject private var pronunciation = PronunciationPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.word).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !entry.phonetic.isEmpty { Text(entry.phonetic).font(.title3).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(action: playPronunciation) {
                    Image(systemName: "speaker.wave.2.fill").font(.title2)
                        .frame(width: 44, height: 44)
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .background(AppTheme.peach, in: Circle())
                    .accessibilityLabel("播放发音")
            }
            .padding(18)
            .background(AppTheme.lemon.opacity(0.65), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let message = pronunciation.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            WordTagsEditor(entryID: entry.id)
            WordMasteryView(entryID: entry.id)
            ReadingContextSection(entryID: entry.id)
            Divider()
            ForEach(currentEntry.groupedMeanings) { meaning in
                VStack(alignment: .leading, spacing: 12) {
                    Text(meaning.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(AppTheme.accent.opacity(0.1), in: Capsule())
                    if !meaning.chineseDefinitions.isEmpty {
                        CardSection(title: "中文释义", content: meaning.chineseDefinitions.joined(separator: "\n"), tint: AppTheme.accent)
                    } else {
                        Text("词库暂无此词性的中文释义").font(.caption).foregroundStyle(.secondary)
                    }
                    if !meaning.englishDefinitions.isEmpty {
                        CardSection(title: "英文解释", content: meaning.englishDefinitions.joined(separator: "\n"), tint: AppTheme.accent)
                    } else {
                        Text("词库暂无此词性的英文解释").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(AppTheme.pastel(Int(meaning.partOfSpeech.unicodeScalars.first?.value ?? 0)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if currentEntry.needsExample {
                if store.loadingExamples.contains(entry.id) {
                    ProgressView("正在补充例句…").font(.footnote)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.exampleMessages[entry.id] ?? "暂无例句")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("获取例句") {
                            Task { await store.supplementExample(for: entry.id) }
                        }
                    }
                }
            } else {
                CardSection(title: "例句 / 用法示例", content: "“\(currentEntry.example)”", tint: AppTheme.accent)
            }
        }
        .padding(28)
        .frame(maxWidth: 680, alignment: .leading)
        .studyCard()
        .onDisappear { pronunciation.stop() }
        .task(id: entry.id) { await store.supplementExample(for: entry.id) }
    }

    private func playPronunciation() {
        pronunciation.play(word: entry.word)
    }
}

@MainActor
private final class PronunciationPlayer: ObservableObject {
    @Published private(set) var message: String?
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")

    func play(word: String) {
        synthesizer.stopSpeaking(at: .immediate)
        message = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            message = "无法启用音频播放，请稍后重试。"
            return
        }
        synthesizer.usesApplicationAudioSession = true
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct CardSection: View {
    let title: String
    let content: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(content).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var word: String? = nil
}

#Preview {
    ContentView().environmentObject(VocabularyStore())
}
