import SwiftUI
import AppKit
@preconcurrency import Vision
import ImageIO

struct MacOCRView: View {
    @EnvironmentObject private var store: VocabularyStore
    @State private var addedEntry: WordEntry?
    let originalImage: NSImage
    let addWord: (String) async -> MacWordAdditionResult
    @Environment(\.dismiss) private var dismiss
    @State private var workingImage: NSImage
    @State private var words: [MacRecognizedWord] = []
    @State private var states: [UUID: MacOCRWordState] = [:]
    @State private var isRecognizing = true
    @State private var showsCropper = false
    @State private var isCropped = false
    @State private var version = 0
    @State private var sourceBook = ""
    @State private var sourcePage = ""

    init(image: NSImage, addWord: @escaping (String) async -> MacWordAdditionResult) {
        originalImage = image
        self.addWord = addWord
        _workingImage = State(initialValue: image)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("图片识词").font(.title2.bold())
                Spacer()
                Menu {
                    Button("裁剪识别区域", systemImage: "crop") { showsCropper = true }
                    Button("恢复原图", systemImage: "arrow.uturn.backward") { apply(originalImage, cropped: false) }
                        .disabled(!isCropped)
                } label: { Label("裁剪", systemImage: "crop") }
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            OCRSourceFields(book: $sourceBook, page: $sourcePage).padding(.horizontal)
            HSplitView {
                ZStack {
                    Color.black
                    Image(nsImage: workingImage).resizable().scaledToFit().padding(18)
                }.frame(minWidth: 360)
                VStack(alignment: .leading, spacing: 12) {
                    if isRecognizing {
                        Spacer(); ProgressView("正在识别英文单词…").frame(maxWidth: .infinity); Spacer()
                    } else if words.isEmpty {
                        ContentUnavailableView("没有识别到英文单词", systemImage: "text.viewfinder", description: Text("请裁剪到清晰的英文文字区域。"))
                    } else {
                        Text("识别到 \(words.count) 个词").font(.headline).padding(.horizontal)
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
                                ForEach(words) { word in
                                    Button { add(word) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(word.text).font(.headline).lineLimit(1)
                                            Label(state(for: word).title, systemImage: state(for: word).icon)
                                                .font(.caption).foregroundStyle(state(for: word).color)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    }
                                    .buttonStyle(.plain)
                                    .help(word.sentence)
                                    .background(state(for: word).color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                                    .disabled(state(for: word) == .adding || state(for: word) == .added || state(for: word) == .duplicate)
                                }
                            }.padding()
                        }
                    }
                }.frame(minWidth: 300)
            }
        }
        .task(id: version) { await recognize(currentVersion: version) }
        .sheet(item: $addedEntry) { entry in
            MacWordDetail(entry: entry)
                .environmentObject(store)
                .frame(minWidth: 580, minHeight: 520)
        }
        .sheet(isPresented: $showsCropper) {
            if let image = workingImage.ocrCGImage {
                MacImageCropView(cgImage: image) { apply($0, cropped: true) }
                    .frame(minWidth: 720, minHeight: 620)
            } else {
                ContentUnavailableView("无法裁剪图片", systemImage: "exclamationmark.triangle")
                    .frame(minWidth: 520, minHeight: 360)
            }
        }
    }

    @MainActor
    private func recognize(currentVersion: Int) async {
        isRecognizing = true
        guard let image = workingImage.ocrCGImage else { isRecognizing = false; return }
        let result = await MacTextRecognizer.recognizeWords(in: image)
        guard currentVersion == version, !Task.isCancelled else { return }
        words = result
        isRecognizing = false
    }

    private func apply(_ image: NSImage, cropped: Bool) {
        workingImage = image
        isCropped = cropped
        words = []
        states = [:]
        isRecognizing = true
        version += 1
    }

    private func state(for word: MacRecognizedWord) -> MacOCRWordState { states[word.id] ?? .ready }
    private func add(_ word: MacRecognizedWord) {
        guard state(for: word) == .ready || state(for: word) == .failed else { return }
        states[word.id] = .adding
        let context = ReadingContext(sentence: word.sentence, bookTitle: sourceBook, page: sourcePage)
        Task {
            let result: MacWordAdditionResult = store.contains(word.text) ? .duplicate : await addWord(word.text)
            if case .failed = result { states[word.id] = .failed; return }
            if let entry = store.entries.first(where: { $0.word.caseInsensitiveCompare(word.text) == .orderedSame }) {
                store.saveReadingContext(context, for: entry.id)
                addedEntry = entry
            }
            switch result {
            case .added:
                states[word.id] = .added
            case .duplicate: states[word.id] = .duplicate
            case .failed: states[word.id] = .failed
            }
        }
    }
}

private enum MacOCRWordState: Equatable {
    case ready, adding, added, duplicate, failed
    var title: String {
        switch self {
        case .ready: return "点击加入"
        case .adding: return "加入中"
        case .added: return "已加入"
        case .duplicate: return "已存在 · 语境已保存"
        case .failed: return "失败，点击重试"
        }
    }
    var icon: String {
        switch self {
        case .ready: return "plus.circle"
        case .adding: return "arrow.triangle.2.circlepath"
        case .added: return "checkmark.circle.fill"
        case .duplicate: return "exclamationmark.circle"
        case .failed: return "arrow.clockwise.circle"
        }
    }
    var color: Color {
        switch self {
        case .ready: return MacTheme.accent
        case .adding: return .orange
        case .added: return .green
        case .duplicate: return .yellow
        case .failed: return .red
        }
    }
}

private struct MacRecognizedWord: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect
    let sentence: String
}

private enum MacTextRecognizer {
    static func recognizeWords(in image: CGImage) async -> [MacRecognizedWord] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let candidates = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    .compactMap { observation -> (VNRecognizedText, CGRect)? in
                        guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.6 else { return nil }
                        return (candidate, observation.boundingBox)
                    }
                let lines = candidates.map { OCRTextLine(text: $0.0.string, box: $0.1) }
                let words = candidates.enumerated().flatMap { index, item -> [MacRecognizedWord] in
                    let candidate = item.0
                    var result: [MacRecognizedWord] = []
                    candidate.string.enumerateSubstrings(in: candidate.string.startIndex..., options: .byWords) { _, range, _, _ in
                        let text = String(candidate.string[range])
                        guard text.count > 1,
                              text.range(of: "^[A-Za-z]+(?:[-'][A-Za-z]+)*$", options: .regularExpression) != nil,
                              let box = try? candidate.boundingBox(for: range) else { return }
                        result.append(MacRecognizedWord(text: text.lowercased(), boundingBox: box.boundingBox,
                            sentence: OCRSentenceExtractor.sentence(lines: lines, lineIndex: index, wordRange: range)))
                    }
                    return result
                }
                .sorted {
                    abs($0.boundingBox.midY - $1.boundingBox.midY) < max($0.boundingBox.height, $1.boundingBox.height) * 0.8
                        ? $0.boundingBox.minX < $1.boundingBox.minX : $0.boundingBox.midY > $1.boundingBox.midY
                }
                var seen = Set<String>()
                continuation.resume(returning: words.filter { seen.insert($0.text + "\n" + $0.sentence).inserted })
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "en-GB"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            }
        }
    }
}

private struct MacImageCropView: View {
    let completion: (NSImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MacCropModel
    @State private var ratio: CGFloat

    init(cgImage: CGImage, completion: @escaping (NSImage) -> Void) {
        self.completion = completion
        let model = MacCropModel(cgImage: cgImage)
        _model = StateObject(wrappedValue: model)
        _ratio = State(initialValue: model.imageRatio)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("裁剪识别区域").font(.title2.bold()); Spacer(); Button("取消") { dismiss() }; Button("使用此区域") { if let result = model.crop() { completion(result); dismiss() } }.buttonStyle(.borderedProminent) }.padding()
            GeometryReader { proxy in
                let viewport = fit(ratio: ratio, inside: CGSize(width: max(proxy.size.width - 30, 1), height: max(proxy.size.height - 20, 1)))
                ZStack {
                    Color.black
                    let display = model.displaySize(viewport: viewport)
                    Image(decorative: model.cgImage, scale: 1).resizable()
                        .frame(width: display.width, height: display.height).offset(model.offset)
                        .frame(width: viewport.width, height: viewport.height).clipped()
                        .overlay { Rectangle().stroke(.white, lineWidth: 2) }
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onChanged { model.drag($0.translation, viewport: viewport) }.onEnded { _ in model.finishDrag() })
                        .simultaneousGesture(MagnificationGesture().onChanged { model.magnify($0, viewport: viewport) }.onEnded { _ in model.finishMagnify() })
                }.onAppear { model.viewport = viewport }.onChange(of: viewport) { _, new in model.viewport = new; model.clamp(viewport: new) }
            }
            Picker("比例", selection: $ratio) {
                Text("原比例").tag(model.imageRatio); Text("1:1").tag(CGFloat(1)); Text("4:3").tag(CGFloat(4.0 / 3)); Text("3:4").tag(CGFloat(3.0 / 4))
            }.pickerStyle(.segmented).frame(maxWidth: 420).onChange(of: ratio) { _, _ in model.reset() }
            Text("拖动调整位置，触控板双指缩放").font(.caption).foregroundStyle(.secondary).padding(.bottom)
        }.background(Color.black).preferredColorScheme(.dark)
    }

    private func fit(ratio: CGFloat, inside size: CGSize) -> CGSize {
        size.width / size.height > ratio ? CGSize(width: size.height * ratio, height: size.height) : CGSize(width: size.width, height: size.width / ratio)
    }
}

@MainActor
private final class MacCropModel: ObservableObject {
    let cgImage: CGImage
    @Published var zoom: CGFloat = 1
    @Published var offset: CGSize = .zero
    var viewport: CGSize = .zero
    private var settledZoom: CGFloat = 1
    private var settledOffset: CGSize = .zero
    var imageRatio: CGFloat { CGFloat(cgImage.width) / CGFloat(cgImage.height) }

    init(cgImage: CGImage) { self.cgImage = cgImage }
    func reset() { zoom = 1; offset = .zero; settledZoom = 1; settledOffset = .zero }
    func displaySize(viewport: CGSize) -> CGSize {
        let base = viewport.width / viewport.height > imageRatio
            ? CGSize(width: viewport.width, height: viewport.width / imageRatio)
            : CGSize(width: viewport.height * imageRatio, height: viewport.height)
        return CGSize(width: base.width * zoom, height: base.height * zoom)
    }
    func drag(_ translation: CGSize, viewport: CGSize) { offset = CGSize(width: settledOffset.width + translation.width, height: settledOffset.height + translation.height); clamp(viewport: viewport) }
    func finishDrag() { settledOffset = offset }
    func magnify(_ value: CGFloat, viewport: CGSize) { zoom = min(max(settledZoom * value, 1), 8); clamp(viewport: viewport) }
    func finishMagnify() { settledZoom = zoom; settledOffset = offset }
    func clamp(viewport: CGSize) {
        let display = displaySize(viewport: viewport)
        let x = max(0, (display.width - viewport.width) / 2), y = max(0, (display.height - viewport.height) / 2)
        offset.width = min(max(offset.width, -x), x); offset.height = min(max(offset.height, -y), y)
    }
    func crop() -> NSImage? {
        let display = displaySize(viewport: viewport)
        let normalized = CGRect(x: ((display.width - viewport.width) / 2 - offset.width) / display.width,
                                y: ((display.height - viewport.height) / 2 - offset.height) / display.height,
                                width: viewport.width / display.width, height: viewport.height / display.height)
        let pixels = CGRect(x: normalized.minX * CGFloat(cgImage.width), y: normalized.minY * CGFloat(cgImage.height),
                            width: normalized.width * CGFloat(cgImage.width), height: normalized.height * CGFloat(cgImage.height)).integral
        guard let cropped = cgImage.cropping(to: pixels) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}

private extension NSImage {
    var ocrCGImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high])
    }
}
