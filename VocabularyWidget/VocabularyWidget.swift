import SwiftUI
import WidgetKit

private struct StudyEntry: TimelineEntry {
    let date: Date
}

private struct StudyProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudyEntry { StudyEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) {
        completion(StudyEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        completion(Timeline(entries: [StudyEntry(date: .now)], policy: .never))
    }
}

private struct StudyWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("单词本", systemImage: "book.closed.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("每天复习\n记得更牢")
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if family == .systemSmall {
                    Label("开始复习", systemImage: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                VStack(spacing: 10) {
                    Link(destination: URL(string: "vocabularylib://review")!) {
                        Label("每日复习", systemImage: "brain.head.profile")
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Link(destination: URL(string: "vocabularylib://add")!) {
                        Label("添加单词", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "vocabularylib://review"))
    }
}

@main
struct VocabularyWidget: Widget {
    let kind = "VocabularyStudyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StudyProvider()) { _ in
            StudyWidgetView()
        }
        .configurationDisplayName("每日单词学习")
        .description("快速打开每日复习或记录新单词。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
