import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#endif

/// Keeps the original recall card while sharing objective exercises across platforms.
struct ReviewExerciseView<RecallCard: View>: View {
    @EnvironmentObject private var store: VocabularyStore
    let entry: WordEntry
    let recallCard: (@escaping (Bool) -> Void) -> RecallCard
    @State private var exercise: WordExercise?
    @State private var answer = ""
    @State private var letters: [String] = []
    @State private var activeBlank = 0
    @ScaledMetric(relativeTo: .title2) private var letterWidth: CGFloat = 32
    @ScaledMetric(relativeTo: .title2) private var letterHeight: CGFloat = 48
    @FocusState private var answerFocused: Bool
    @StateObject private var speech = ExerciseSpeech()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let exercise {
                Label(exercise.mode.title, systemImage: icon(exercise.mode))
                    .font(.headline).foregroundStyle(.tint)
                    .accessibilityIdentifier("exerciseMode")
                Text("四种题型随机轮换 · 同词一轮内不重复")
                    .font(.caption).foregroundStyle(.secondary)
                if exercise.mode == .recognition {
                    recallCard { remembered in
                        store.completeExercise(for: entry, id: exercise.id, recognition: remembered)
                    }
                } else {
                    objectiveCard(exercise)
                }
            } else { ProgressView("准备练习…") }
        }
        .task(id: entry.id) {
            let prepared = store.exercise(for: entry)
            exercise = prepared
            answer = prepared.submittedAnswer ?? ""
            letters = Array(repeating: "", count: prepared.missingIndices.count)
            if let submitted = prepared.submittedAnswer {
                for (index, letter) in submitted.enumerated() where index < letters.count { letters[index] = String(letter) }
            }
            activeBlank = 0
            if prepared.mode == .listeningSpelling && prepared.correct == nil { speech.play(entry.word) }
        }
        .onDisappear { speech.stop(); answerFocused = false }
    }

    private func icon(_ mode: ExerciseMode) -> String {
        switch mode {
        case .recognition: return "brain.head.profile"
        case .chineseSpelling: return "character.book.closed"
        case .listeningSpelling: return "ear"
        case .missingLetters: return "character.cursor.ibeam"
        }
    }

    private func objectiveCard(_ exercise: WordExercise) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if exercise.mode == .listeningSpelling {
                Text("听发音，输入完整的英文单词")
                Button { speech.play(entry.word) } label: {
                    Label("播放发音", systemImage: "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }.buttonStyle(.borderedProminent)
                Text("只接受当前收录词的拼写；同音词有歧义时，可查看答案后继续学习。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(entry.chineseDefinition.isEmpty ? "本词暂无中文释义，可选择“不会，查看答案”。" : entry.chineseDefinition.replacingOccurrences(of: entry.word, with: "（本词）", options: .caseInsensitive))
                    .font(.title3).fixedSize(horizontal: false, vertical: true)
                if exercise.mode == .missingLetters {
                    missingWord(exercise)
                    Text("点选下方字母填入横线；点击横线可修改。共 \(exercise.missingIndices.count) 处缺字。")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("根据中文释义，输入单词本中的英文单词。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let message = speech.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let correct = exercise.correct {
                Label(correct ? "回答正确" : "这次还需要练习", systemImage: correct ? "checkmark.circle.fill" : "arrow.clockwise")
                    .font(.headline).foregroundStyle(correct ? Color.green : Color.orange)
                    .accessibilityIdentifier("exerciseResult")
                Text("正确单词：\(entry.word)").font(.title2.bold())
                if exercise.mode == .missingLetters {
                    Text("缺失字母：\(exercise.expectedAnswer(for: entry.word))")
                }
                if !correct { Text("你的答案：\(exercise.submittedAnswer?.isEmpty == false ? exercise.submittedAnswer! : "未作答")").foregroundStyle(.secondary) }
                Text(entry.chineseDefinition).font(.subheadline)
                ReadingContextSection(entryID: entry.id, editable: false)
                Button("保存并继续") {
                    speech.stop()
                    store.completeExercise(for: entry, id: exercise.id)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("exerciseContinue")
                Text("继续后记录本次成绩；答错的词将在 10 分钟后换一种方式重练。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if exercise.mode == .missingLetters {
                    letterChoices(exercise)
                } else {
                TextField("输入英文单词", text: $answer)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    #endif
                    .focused($answerFocused)
                    .submitLabel(.done)
                    .onSubmit { if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { check(exercise, answer: answer) } }
                    .accessibilityIdentifier("exerciseAnswer")
                }
                HStack {
                    Button("检查答案") { check(exercise, answer: exercise.mode == .missingLetters ? letters.joined() : answer) }
                        .buttonStyle(.borderedProminent)
                        .disabled(exercise.mode == .missingLetters ? letters.isEmpty || letters.contains("") : answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("exerciseCheck")
                    Button("不会，查看答案") { check(exercise, answer: "") }.buttonStyle(.bordered)
                }
                Text("检查后不能改答；忽略大小写及首尾空格。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.12)) }
    }

    private func missingWord(_ exercise: WordExercise) -> some View {
        let characters = Array(entry.word)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: letterWidth, maximum: letterWidth), spacing: 6)], alignment: .leading, spacing: 12) {
            ForEach(characters.indices, id: \.self) { position in
                if let slot = exercise.missingIndices.firstIndex(of: position) {
                    Button { if exercise.correct == nil { activeBlank = slot } } label: {
                        letterCell(letters.indices.contains(slot) && !letters[slot].isEmpty ? letters[slot] : " ",
                                   blank: true, active: exercise.correct == nil && activeBlank == slot)
                    }.buttonStyle(.plain).allowsHitTesting(exercise.correct == nil)
                        .accessibilityLabel("第 \(slot + 1) 处缺字")
                        .accessibilityValue(letters.indices.contains(slot) && !letters[slot].isEmpty ? letters[slot] : "空白")
                        .accessibilityIdentifier("missingSlot-\(slot)")
                } else {
                    letterCell(String(characters[position]), blank: false, active: false)
                        .accessibilityIdentifier("fixedLetter-\(position)")
                }
            }
        }
    }

    /// All glyphs use exactly the same font and frame. Decorations are overlays,
    /// so neither an underline nor selection changes the glyph's vertical position.
    private func letterCell(_ glyph: String, blank: Bool, active: Bool) -> some View {
        Text(glyph)
            .font(.system(.title2, design: .monospaced, weight: .semibold))
            .foregroundStyle(Color.primary)
            .frame(width: letterWidth, height: letterHeight)
            .background(active ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) {
                if blank {
                    Rectangle().fill(active ? Color.accentColor : Color.primary.opacity(0.55))
                        .frame(height: 2).padding(.bottom, 4)
                        .allowsHitTesting(false)
                }
            }
    }

    private func letterChoices(_ exercise: WordExercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(exercise.candidateLetters ?? [], id: \.self) { letter in
                    Button {
                        guard letters.indices.contains(activeBlank) else { return }
                        letters[activeBlank] = letter
                        if let next = letters.indices.first(where: { letters[$0].isEmpty }) { activeBlank = next }
                    } label: {
                        Text(letter).font(.system(.title2, design: .monospaced, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: letterHeight)
                    }.buttonStyle(.bordered)
                        .disabled(letters.enumerated().contains { $0.offset != activeBlank && $0.element == letter })
                        .accessibilityIdentifier("candidate-\(letter)")
                }
            }
            HStack {
                Button("清除当前格") { if letters.indices.contains(activeBlank) { letters[activeBlank] = "" } }
                Spacer()
                Button("重新填写") { letters = Array(repeating: "", count: exercise.missingIndices.count); activeBlank = 0 }
            }.font(.subheadline)
        }
    }

    private func check(_ exercise: WordExercise, answer: String) {
        answerFocused = false
        self.exercise = store.gradeExercise(for: entry, id: exercise.id, answer: answer)
    }
}

struct WordMasteryView: View {
    @EnvironmentObject private var store: VocabularyStore
    let entryID: UUID
    var body: some View {
        let record = store.reviews[entryID.uuidString]
        VStack(alignment: .leading, spacing: 8) {
            Text("学习掌握情况").font(.headline)
            Text("认识（自评）：\((record?.recognitionScore ?? SkillScore()).summary)")
            Text("拼写（作答）：\((record?.spellingScore ?? SkillScore()).summary)")
            ForEach(ExerciseMode.allCases.filter { $0 != .recognition }, id: \.rawValue) { mode in
                if let score = record?.exerciseScores?[mode.rawValue], score.attempts > 0 {
                    Text("\(mode.title)：\(score.summary)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("认识与拼写独立记录；填空有字母提示，分模式查看更准确。旧版记录不推算为拼写成绩。")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
private final class ExerciseSpeech: ObservableObject {
    @Published var message: String?
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")
    func play(_ word: String) {
        stop()
        message = nil
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { message = "无法启用声音，请检查音量或音频设备。"; return }
        #endif
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
