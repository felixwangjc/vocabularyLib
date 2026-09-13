import SwiftUI

struct ReviewView: View {
  @EnvironmentObject private var store: VocabularyStore

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let due = store.dueWords(at: context.date)
      ScrollViewReader { reader in
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            HStack {
              Label("待学习 \(due.count)", systemImage: "book")
              Spacer()
              Text("今日已学 \(store.reviewedToday(at: context.date)) 词")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(16)
            .studyCard()
            .accessibilityIdentifier("reviewSummary")
            .id("reviewTop")

            if let entry = due.first {
              Text(store.reviews[entry.id.uuidString] == nil ? "新词学习" : "到期复习")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.accent.opacity(0.1), in: Capsule())
              ReviewSwipeCard(entry: entry, remainingCount: due.count) { remembered in
                store.review(entry, remembered: remembered)
              }
              .id(entry.id)
            } else {
              ContentUnavailableView(
                store.entries.isEmpty ? "先添加一些单词" : "当前学习任务已完成",
                systemImage: store.entries.isEmpty ? "book.closed" : "checkmark.circle",
                description: Text(
                  store.entries.isEmpty ? "加入单词本的单词会自动进入学习计划。" : "到期的单词会自动出现，记得每天回来复习。")
              )
              if let next = store.entries.compactMap({ store.reviews[$0.id.uuidString]?.dueAt })
                .min()
              {
                Text("下次复习：\(next.formatted(date: .abbreviated, time: .shortened))")
                  .foregroundStyle(.secondary)
              }
            }
            Divider()
            Text("记住后按 1、2、4、7、15、30、60 天逐步延长间隔；忘记后重置并在 10 分钟后重练。这是基于间隔重复的学习安排，并非对个人遗忘速度的精确预测。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(20)
          .frame(maxWidth: 720)
          .frame(maxWidth: .infinity)
        }
        .onChange(of: due.first?.id) { _, _ in
          reader.scrollTo("reviewTop", anchor: .top)
        }
      }
    }
    .navigationTitle("每日复习")
    .background(AppTheme.canvas)
  }
}

private struct ReviewSwipeCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let entry: WordEntry
  let remainingCount: Int
  let onAnswer: (Bool) -> Void

  @State private var revealed = false
  @State private var cardWidth: CGFloat = 320
  @State private var exitOffset: CGFloat = 0
  @State private var committing = false
  @State private var active = true
  @State private var submissionID: UUID?
  @State private var drag = ReviewDrag()
  @GestureState private var isDragging = false

  private var threshold: CGFloat { min(140, max(80, cardWidth * 0.28)) }
  private var offset: CGFloat { committing ? exitOffset : drag.translation }
  private var progress: Double { min(1, abs(offset) / threshold) }
  private var feedbackColor: Color { offset < 0 ? .green : .orange }

  var body: some View {
    VStack(spacing: 22) {
      HStack {
        Label("左滑 · 记住了", systemImage: "arrow.left")
          .foregroundStyle(.green)
        Spacer(minLength: 8)
        Label("右滑 · 再次复习", systemImage: "arrow.right")
          .foregroundStyle(.orange)
      }
      .font(.subheadline.weight(.medium))
      .accessibilityElement(children: .combine)

      cardContent
        .frame(maxWidth: .infinity)
        .background {
          GeometryReader { proxy in
            Color.clear
              .onAppear { cardWidth = proxy.size.width }
              .onChange(of: proxy.size.width) { _, width in cardWidth = width }
          }
        }
        .overlay {
          RoundedRectangle(cornerRadius: 24)
            .strokeBorder(feedbackColor.opacity(progress), lineWidth: 3)
            .background(
              feedbackColor.opacity(progress * 0.07), in: RoundedRectangle(cornerRadius: 24)
            )
            .allowsHitTesting(false)
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset / cardWidth) * 10))
        .offset(x: reduceMotion ? 0 : offset)
        .opacity(committing ? 0 : 1)
        .background {
          if remainingCount > 1 {
            RoundedRectangle(cornerRadius: 24)
              .fill(AppTheme.surface)
              .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.07)))
              .scaleEffect(x: 0.95, y: 1)
              .offset(y: 10)
              .zIndex(-1)
          }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipeGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewSwipeCard")
        .accessibilityAction(named: "记住了") { submit(remembered: true) }
        .accessibilityAction(named: "再次复习") { submit(remembered: false) }

      Text(
        progress > 0
          ? (progress >= 1 ? (offset < 0 ? "松手，记住这个词" : "松手，10 分钟后再次复习") : "继续滑动，或松手取消")
          : "左右滑动卡片，或点击下方按钮"
      )
      .font(.caption)
      .foregroundStyle(progress > 0 ? feedbackColor : .secondary)
      .accessibilityIdentifier("reviewSwipeHint")

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { answerButtons }
        VStack(spacing: 12) { answerButtons }
      }
      .frame(maxWidth: .infinity)
    }
    .disabled(committing)
    .onChange(of: isDragging) { _, dragging in
      // Also spring back if the system cancels the gesture (rotation, scroll, interruption).
      if !dragging, !committing { resetDrag() }
    }
    .onAppear { active = true }
    .onDisappear {
      active = false
      submissionID = nil
      committing = false
      exitOffset = 0
      drag = ReviewDrag()
    }
  }

  @ViewBuilder private var cardContent: some View {
    if revealed {
      WordCard(entry: entry)
    } else {
      VStack(spacing: 28) {
        Image(systemName: "brain.head.profile")
          .font(.largeTitle).foregroundStyle(AppTheme.accent)
        Text(entry.word)
          .font(.system(.largeTitle, design: .rounded, weight: .bold))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        Text("先回想这个单词的含义\n也可以查看答案后再判断")
          .font(.subheadline).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("查看释义与发音") { revealed = true }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
      }
      .padding(28)
      .frame(maxWidth: .infinity, minHeight: 330)
      .studyCard()
    }
  }

  @ViewBuilder private var answerButtons: some View {
    Button {
      submit(remembered: true)
    } label: {
      Label("记住了", systemImage: "arrow.left.circle.fill")
        .padding(.vertical, 6)
    }
    .buttonStyle(.bordered).tint(.green)
    .accessibilityIdentifier("reviewRemembered")
    Button {
      submit(remembered: false)
    } label: {
      Label("再次复习", systemImage: "arrow.right.circle.fill")
        .padding(.vertical, 6)
    }
    .buttonStyle(.bordered).tint(.orange)
    .accessibilityIdentifier("reviewAgain")
  }

  private var swipeGesture: some Gesture {
    DragGesture(minimumDistance: 18)
      .updating($isDragging) { _, state, _ in state = true }
      .onChanged { value in
        guard !committing else { return }
        // Lock the initial direction so vertical reading never becomes an answer.
        if drag.horizontal == nil {
          drag.horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.2
        }
        if drag.horizontal == true { drag.translation = value.translation.width }
      }
      .onEnded { value in
        if drag.horizontal == true, abs(value.translation.width) >= threshold {
          submit(remembered: value.translation.width < 0)
        } else {
          resetDrag()
        }
      }
  }

  private func resetDrag() {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      drag = ReviewDrag()
    }
  }

  private func submit(remembered: Bool) {
    guard !committing, active else { return }
    // One answer only, even if a button and a gesture finish together.
    let token = UUID()
    submissionID = token
    withAnimation(
      .easeIn(duration: reduceMotion ? 0.12 : 0.24), completionCriteria: .logicallyComplete
    ) {
      committing = true
      exitOffset = (remembered ? -1 : 1) * (cardWidth + 80)
    } completion: {
      guard active, submissionID == token else { return }
      submissionID = nil
      onAnswer(remembered)
    }
  }
}

private struct ReviewDrag {
  var horizontal: Bool?
  var translation: CGFloat = 0
}
