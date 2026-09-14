import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct MacContentView: View {
    @EnvironmentObject private var store: VocabularyStore
    @State private var section: MacSection = .add
    @State private var selectedEntry: WordEntry?
    @State private var ocrImage: MacImageItem?
    @State private var alert: MacAlert?

    var body: some View {
        NavigationSplitView {
            List(MacSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
                    .padding(.vertical, 5)
            }
            .navigationTitle("Vocabulary Lib")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Image(systemName: "books.vertical.fill").foregroundStyle(MacTheme.accent)
                    Text("\(store.entries.count) 个单词")
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        } detail: {
            Group {
                switch section {
                case .add: MacAddWordView(showAlert: { alert = $0 })
                case .book: MacWordBookView(selectedEntry: $selectedEntry)
                case .review: MacReviewView()
                case .settings: MacSettingsView()
                }
            }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("粘贴剪贴板图片", systemImage: "doc.on.clipboard") { pasteImage() }
                        Button("从文件导入图片", systemImage: "folder") { importImage() }
                    } label: {
                        Label("图片识词", systemImage: "text.viewfinder")
                    }
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            MacWordDetail(entry: entry)
                .environmentObject(store)
                .frame(minWidth: 580, minHeight: 520)
        }
        .sheet(item: $ocrImage) { item in
            MacOCRView(image: item.image, addWord: addRecognizedWord)
                .frame(minWidth: 760, minHeight: 650)
        }
        .alert(item: $alert) { value in
            Alert(title: Text(value.title), message: Text(value.message), dismissButton: .default(Text("知道了")))
        }
    }

    private func pasteImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            alert = MacAlert(title: "无法粘贴", message: "剪贴板中没有可读取的图片。")
            return
        }
        ocrImage = MacImageItem(image: image)
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else {
                if response == .OK { alert = MacAlert(title: "无法导入", message: "无法读取所选图片。") }
                return
            }
            ocrImage = MacImageItem(image: image)
        }
    }

    private func addRecognizedWord(_ word: String) async -> MacWordAdditionResult {
        guard !store.contains(word) else { return .duplicate }
        do { return try await store.add(word: word) ? .added : .duplicate }
        catch { return .failed(error.localizedDescription) }
    }
}

private enum MacSection: String, CaseIterable, Identifiable {
    case add, book, review, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .add: return "输入单词"
        case .book: return "单词本"
        case .review: return "每日复习"
        case .settings: return "设置"
        }
    }
    var icon: String {
        switch self {
        case .add: return "text.cursor"
        case .book: return "books.vertical"
        case .review: return "brain.head.profile"
        case .settings: return "gearshape"
        }
    }
}

private struct MacAddWordView: View {
    @EnvironmentObject private var store: VocabularyStore
    @State private var word = ""
    let showAlert: (MacAlert) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("输入单词").font(.system(size: 38, weight: .black, design: .rounded))
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Image(systemName: "character.book.closed.fill")
                            .font(.system(size: 30)).foregroundStyle(MacTheme.accent)
                            .frame(width: 62, height: 62).background(MacTheme.peach, in: RoundedRectangle(cornerRadius: 18))
                        Spacer()
                        Image(systemName: "sparkles").font(.title).foregroundStyle(MacTheme.accent)
                    }
                    Text("每一个新词，都是一点进步。")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("本地查词，即刻收藏；例句会在联网时自动补充。")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        TextField("例如：serendipity", text: $word)
                            .textFieldStyle(.plain).font(.title3).padding(14)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            .onSubmit(add)
                        Button(action: add) { Label("加入", systemImage: "plus.circle.fill").padding(.horizontal, 8) }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.isLoading)
                    }
                    if store.isLoading { ProgressView("正在查找释义…") }
                }
                .padding(28).macCard()

                HStack(spacing: 14) {
                    MacFeature(title: "中英文释义", icon: "character.book.closed", color: MacTheme.mint)
                    MacFeature(title: "系统发音", icon: "speaker.wave.2", color: MacTheme.sky)
                    MacFeature(title: "例句补充", icon: "text.quote", color: MacTheme.lemon)
                }
            }
            .padding(34).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(MacTheme.canvas)
    }

    private func add() {
        let input = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        guard !store.contains(input) else {
            showAlert(MacAlert(title: "单词已存在", message: "“\(input)” 已经在单词本中。")); return
        }
        Task {
            do {
                if try await store.add(word: input) {
                    word = ""
                    showAlert(MacAlert(title: "已加入单词本", message: "“\(input)” 已保存。"))
                }
            } catch { showAlert(MacAlert(title: "添加失败", message: error.localizedDescription)) }
        }
    }
}

private struct MacFeature: View {
    let title: String
    let icon: String
    let color: Color
    var body: some View {
        Label(title, systemImage: icon).font(.headline).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.primary)
            .background(color, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.10)) }
    }
}

private struct MacWordBookView: View {
    @EnvironmentObject private var store: VocabularyStore
    @Binding var selectedEntry: WordEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("单词本").font(.system(size: 38, weight: .black, design: .rounded))
                Spacer()
                Text("\(store.entries.count) 个单词").foregroundStyle(.secondary)
            }.padding(.horizontal, 30).padding(.top, 28)
            if store.entries.isEmpty {
                ContentUnavailableView("还没有单词", systemImage: "text.book.closed", description: Text("从输入单词开始记录。"))
            } else {
                List {
                    ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                        Button { selectedEntry = entry } label: { MacWordRow(entry: entry, index: index) }
                            .buttonStyle(.plain).listRowBackground(Color.clear).listRowSeparator(.hidden)
                            .contextMenu { Button("删除", role: .destructive) { store.delete(at: IndexSet(integer: index)) } }
                    }
                    .onDelete(perform: store.delete)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.background(MacTheme.canvas)
    }
}

private struct MacWordRow: View {
    @EnvironmentObject private var store: VocabularyStore
    let entry: WordEntry
    let index: Int
    private var record: ReviewRecord? { store.reviews[entry.id.uuidString] }
    var body: some View {
        HStack(spacing: 14) {
            Text(String(entry.word.prefix(1)).uppercased()).font(.title2.bold()).foregroundStyle(MacTheme.accent)
                .frame(width: 48, height: 48).background(MacTheme.monogram, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.word).font(.title3.bold())
                Text(entry.chineseDefinition.replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).foregroundStyle(.secondary)
            }
            Spacer()
            Text("复习 \(record?.reviewCount ?? 0) 次").font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(15).frame(maxWidth: .infinity)
        .foregroundStyle(.primary)
        .background(MacTheme.pastel(index), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.10)) }
    }
}

struct MacWordDetail: View {
    @EnvironmentObject private var store: VocabularyStore
    @Environment(\.dismiss) private var dismiss
    let entry: WordEntry
    @State private var speaker = AVSpeechSynthesizer()
    private var current: WordEntry { store.entries.first(where: { $0.id == entry.id }) ?? entry }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entry.word.capitalized).font(.title2.bold())
                Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.word).font(.system(size: 42, weight: .black, design: .rounded))
                            if !entry.phonetic.isEmpty { Text(entry.phonetic).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button { speak() } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.title2).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).foregroundStyle(MacTheme.accent).background(MacTheme.peach, in: Circle())
                    }
                    .padding(20)
                    .foregroundStyle(.primary)
                    .background(MacTheme.lemon, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.12)) }
                    ForEach(current.groupedMeanings) { meaning in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(meaning.title).font(.headline).foregroundStyle(MacTheme.accent)
                            if !meaning.chineseDefinitions.isEmpty { Text(meaning.chineseDefinitions.joined(separator: "\n")) }
                            if !meaning.englishDefinitions.isEmpty { Text(meaning.englishDefinitions.joined(separator: "\n")).foregroundStyle(.secondary) }
                        }.padding(18).macCard(MacTheme.sky, cornerRadius: 20)
                    }
                    if current.needsExample {
                        ProgressView("正在补充例句…")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("例句").font(.headline).foregroundStyle(MacTheme.accent)
                            Text("“\(current.example)”")
                        }.padding(18).macCard(MacTheme.peach, cornerRadius: 20)
                    }
                }.padding(24)
            }
        }
        .task(id: entry.id) { await store.supplementExample(for: entry.id) }
    }

    private func speak() {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: entry.word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        speaker.speak(utterance)
    }
}

private struct MacReviewView: View {
    @EnvironmentObject private var store: VocabularyStore
    @State private var revealed = false
    @State private var dragX: CGFloat = 0
    var body: some View {
        let due = store.dueWords(at: .now)
        VStack(spacing: 24) {
            HStack {
                Text("每日复习").font(.system(size: 38, weight: .black, design: .rounded))
                Spacer(); Text("待学习 \(due.count) · 今日已学 \(store.reviewedToday(at: .now))")
            }
            if let entry = due.first {
                VStack(spacing: 20) {
                    HStack { Label("左滑 · 记住", systemImage: "arrow.left").foregroundStyle(.green); Spacer(); Label("右滑 · 再次复习", systemImage: "arrow.right").foregroundStyle(MacTheme.accent) }
                    if revealed { MacWordDetailBody(entry: entry) }
                    else {
                        Spacer(); Image(systemName: "brain.head.profile").font(.system(size: 44)).foregroundStyle(MacTheme.accent)
                        Text(entry.word).font(.system(size: 46, weight: .black, design: .rounded))
                        Button("查看释义") { revealed = true }.buttonStyle(.borderedProminent).controlSize(.large)
                        Spacer()
                    }
                    HStack {
                        Button("记住了") { answer(entry, true) }.tint(.green)
                        Button("再次复习") { answer(entry, false) }.tint(MacTheme.accent)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                }
                .padding(24).macCard().offset(x: dragX).rotationEffect(.degrees(Double(dragX / 80)))
                .gesture(DragGesture().onChanged { dragX = $0.translation.width }.onEnded { value in
                    if abs(value.translation.width) > 120 { answer(entry, value.translation.width < 0) }
                    withAnimation(.spring) { dragX = 0 }
                })
            } else {
                ContentUnavailableView("当前学习任务已完成", systemImage: "checkmark.circle", description: Text("到期单词会自动出现。"))
            }
            Spacer()
        }.padding(34).background(MacTheme.canvas)
    }
    private func answer(_ entry: WordEntry, _ remembered: Bool) { store.review(entry, remembered: remembered); revealed = false }
}

private struct MacWordDetailBody: View {
    let entry: WordEntry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.word).font(.largeTitle.bold())
                ForEach(entry.groupedMeanings) { meaning in
                    Text(meaning.title).font(.headline).foregroundStyle(MacTheme.accent)
                    Text(meaning.chineseDefinitions.joined(separator: "\n"))
                    Text(meaning.englishDefinitions.joined(separator: "\n")).foregroundStyle(.secondary)
                }
                if !entry.example.isEmpty { Text("“\(entry.example)”").italic() }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 390)
    }
}

private struct MacSettingsView: View {
    @EnvironmentObject private var store: VocabularyStore
    var body: some View {
        Form {
            Section("本地存储") {
                LabeledContent("单词数量", value: "\(store.entries.count)")
                Text("macOS 版本当前使用本地存储，不进行设备间同步。")
            }
            Section("词典与识别") {
                Text("释义来自内置 ECDICT；例句优先读取 WordNet，发音使用 macOS 系统朗读，图片文字识别在设备上完成。")
            }
        }.formStyle(.grouped).padding().navigationTitle("设置")
    }
}

struct MacImageItem: Identifiable {
    let id = UUID()
    let image: NSImage
}

enum MacWordAdditionResult { case added, duplicate, failed(String) }

struct MacAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
