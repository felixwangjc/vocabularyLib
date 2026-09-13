import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: VocabularyStore

    var body: some View {
        Form {
            Section("本地存储") {
                Label("单词与复习进度保存在此设备", systemImage: "internaldrive")
                LabeledContent("单词数量", value: "\(store.entries.count)")
                Text("当前为本地版，不进行设备间同步。已有单词和复习记录继续保留；卸载 App 会移除本地数据。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("词典与识别") {
                Text("网络查词失败时，可打开系统词典查看释义。首次使用请前往系统“设置 → 通用 → 词典”，选择并下载英语或英汉词典。下载后可离线查阅。App 无法代替你下载或指定系统词库，也不能提取系统释义保存。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("优先使用 ECDICT 本地词典查询释义。例句优先读取本地 WordNet 用法示例，未收录时后台联网补充；部分示例为短语，且不保证对应当前展示的首个义项。失败不影响单词保存。发音使用系统英文朗读，照片文字识别在设备上完成。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("开源词库") {
                NavigationLink("WordNet 用法示例许可") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "WordNet-LICENSE", withExtension: "txt")
                            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "许可随 App 例句库附带。")
                            .font(.footnote).padding().textSelection(.enabled)
                    }
                    .navigationTitle("WordNet 许可")
                }
                Link("ECDICT · 英汉双解词库", destination: URL(string: "https://github.com/skywind3000/ECDICT")!)
                NavigationLink("词库许可") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "ECDICT-LICENSE", withExtension: "txt")
                            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "许可随 App 词库附带。")
                            .font(.footnote).padding().textSelection(.enabled)
                    }
                    .navigationTitle("ECDICT 许可")
                }
            }
        }
        .navigationTitle("设置")
    }
}
