import SwiftUI
import UIKit
import Vision
import ImageIO

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if picker.sourceType == .camera { picker.cameraCaptureMode = .photo }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.dismiss()
                return
            }
            parent.onImage(image)
            parent.dismiss()
        }
    }
}

struct OCRReviewView: View {
    let image: UIImage
    let addWord: (String) async -> WordAdditionResult
    @Environment(\.dismiss) private var dismiss
    @State private var words: [RecognizedWord] = []
    @State private var addedWordIDs = Set<UUID>()
    @State private var addingWordIDs = Set<UUID>()
    @State private var duplicateWordIDs = Set<UUID>()
    @State private var failedWordIDs = Set<UUID>()
    @State private var selectedWordID: UUID?
    @State private var dictionaryTerm: DictionaryTerm?
    @State private var isRecognizing = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isRecognizing {
                    Spacer()
                    ProgressView("正在识别照片中的英文单词…")
                    Spacer()
                } else if words.isEmpty {
                    ContentUnavailableView("没有识别到英文单词", systemImage: "text.viewfinder", description: Text("请拍摄清晰、文字朝上的英文内容。"))
                } else {
                    OCRPhotoOverlay(image: image, selectedWord: words.first { $0.id == selectedWordID })
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("识别到 \(words.count) 个词", systemImage: "text.word.spacing")
                                .font(.headline)
                            Spacer()
                            Text("长按 2 秒加入")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                            ForEach(words) { word in
                                OCRWordChip(
                                    word: word,
                                    state: state(for: word),
                                    isSelected: selectedWordID == word.id,
                                    select: { selectedWordID = word.id },
                                    add: { add(word) }
                                )
                                .contextMenu {
                                    if failedWordIDs.contains(word.id) {
                                        Button("查看系统词典") { dictionaryTerm = DictionaryTerm(word: word.text) }
                                    }
                                }
                            }
                        }
                    }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .task { await recognizeText() }
        .sheet(item: $dictionaryTerm) { term in SystemDictionaryView(word: term.word) }
    }

    @MainActor
    private func recognizeText() async {
        isRecognizing = true
        words = await TextRecognizer.recognizeWords(in: image)
        isRecognizing = false
    }

    private func add(_ word: RecognizedWord) {
        guard !addedWordIDs.contains(word.id), !addingWordIDs.contains(word.id) else { return }
        failedWordIDs.remove(word.id)
        addingWordIDs.insert(word.id)
        Task { @MainActor in
            let result = await addWord(word.text)
            addingWordIDs.remove(word.id)
            switch result {
            case .added: addedWordIDs.insert(word.id)
            case .duplicate: duplicateWordIDs.insert(word.id)
            case .failed: failedWordIDs.insert(word.id)
            }
        }
    }

    private func state(for word: RecognizedWord) -> OCRWordState {
        if addedWordIDs.contains(word.id) { return .added }
        if addingWordIDs.contains(word.id) { return .adding }
        if duplicateWordIDs.contains(word.id) { return .duplicate }
        if failedWordIDs.contains(word.id) { return .failed }
        return .ready
    }
}

private struct OCRPhotoOverlay: View {
    let image: UIImage
    let selectedWord: RecognizedWord?
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let imageRatio = max(image.size.width / image.size.height, 0.01)
            let availableRatio = proxy.size.width / max(proxy.size.height, 0.01)
            let displaySize = availableRatio > imageRatio
                ? CGSize(width: proxy.size.height * imageRatio, height: proxy.size.height)
                : CGSize(width: proxy.size.width, height: proxy.size.width / imageRatio)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: displaySize.width, height: displaySize.height)

                if let word = selectedWord {
                    let box = word.boundingBox
                    let boxSize = CGSize(
                        width: max(box.width * displaySize.width, 8),
                        height: max(box.height * displaySize.height, 8)
                    )
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.yellow, lineWidth: 3)
                        .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        .frame(width: boxSize.width, height: boxSize.height)
                    .position(x: box.midX * displaySize.width, y: (1 - box.midY) * displaySize.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .offset(offset)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) {
                withAnimation(.spring) {
                    scale = 1
                    settledScale = 1
                    offset = .zero
                    settledOffset = .zero
                }
            }
        }
        .clipped()
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(settledScale * value, 1), 5)
            }
            .onEnded { _ in
                settledScale = scale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                if scale > 1 { settledOffset = offset }
            }
    }
}

private enum OCRWordState {
    case ready
    case adding
    case added
    case duplicate
    case failed

    var title: String {
        switch self {
        case .ready: return "长按加入"
        case .adding: return "加入中"
        case .added: return "已加入"
        case .duplicate: return "重复添加"
        case .failed: return "添加失败"
        }
    }

    var tint: Color {
        switch self {
        case .ready: return .blue
        case .adding: return .orange
        case .added: return .green
        case .duplicate, .failed: return .red
        }
    }
}

private struct OCRWordChip: View {
    let word: RecognizedWord
    let state: OCRWordState
    let isSelected: Bool
    let select: () -> Void
    let add: () -> Void
    @State private var isPressing = false
    @State private var holdProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(word.text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                if isPressing && state == .ready {
                    Text("按住中…")
                } else {
                    Image(systemName: icon)
                    Text(state.title)
                }
            }
            .font(.caption2)
            .foregroundStyle(state.tint)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(10)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.yellow : state.tint.opacity(0.25), lineWidth: isSelected ? 2 : 1)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .trim(from: 0, to: holdProgress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .opacity(isPressing && state == .ready ? 1 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { select() }
        .onLongPressGesture(minimumDuration: 2, maximumDistance: 18, pressing: { pressing in
            guard state == .ready else { return }
            isPressing = pressing
            if pressing {
                holdProgress = 0
                withAnimation(.linear(duration: 2)) { holdProgress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.15)) { holdProgress = 0 }
            }
        }, perform: add)
        .accessibilityElement(children: .combine)
        .accessibilityHint(state == .ready ? "长按两秒将单词加入单词本" : state.title)
    }

    private var background: Color {
        if isSelected { return Color.yellow.opacity(0.12) }
        return state.tint.opacity(0.08)
    }

    private var icon: String {
        switch state {
        case .ready: return "hand.tap"
        case .adding: return "arrow.triangle.2.circlepath"
        case .added: return "checkmark.circle.fill"
        case .duplicate: return "exclamationmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

private struct RecognizedWord: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect
}

private enum TextRecognizer {
    static func recognizeWords(in image: UIImage) async -> [RecognizedWord] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let words = (request.results as? [VNRecognizedTextObservation] ?? []).flatMap { observation -> [RecognizedWord] in
                    guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.6 else { return [] }
                    var found: [RecognizedWord] = []
                    candidate.string.enumerateSubstrings(in: candidate.string.startIndex..., options: .byWords) { _, range, _, _ in
                        let text = String(candidate.string[range])
                        guard text.count > 1,
                              text.range(of: "^[A-Za-z]+(?:[-'][A-Za-z]+)*$", options: .regularExpression) != nil,
                              let box = try? candidate.boundingBox(for: range) else { return }
                        found.append(RecognizedWord(text: text.lowercased(), boundingBox: box.boundingBox))
                    }
                    return found
                }
                let sorted = words.sorted(by: isBeforeInReadingOrder)
                var seen = Set<String>()
                continuation.resume(returning: sorted.filter { seen.insert($0.text).inserted })
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "en-GB"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImageOrientation, options: [:]).perform([request])
            }
        }
    }

    private static func isBeforeInReadingOrder(_ lhs: RecognizedWord, _ rhs: RecognizedWord) -> Bool {
        let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        let sameLineTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.8
        if verticalDistance <= sameLineTolerance {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.boundingBox.midY > rhs.boundingBox.midY
    }
}

private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
