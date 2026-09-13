import SwiftUI
import UIKit

struct DictionaryTerm: Identifiable {
    let id = UUID()
    let word: String
}

struct SystemDictionaryView: View {
    let word: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack {
                Text("系统释义仅供查阅，不会自动保存到单词本。")
                    .font(.footnote).foregroundStyle(.secondary).padding()
                if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word) {
                    DictionaryController(word: word)
                } else {
                    ContentUnavailableView("系统词典暂无此词", systemImage: "book.closed", description: Text("请检查拼写，或前往系统“设置 → 通用 → 词典”下载英语及英汉词典，再重新打开查询。"))
                }
            }
            .navigationTitle(word)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct DictionaryController: UIViewControllerRepresentable {
    let word: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: word)
    }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
