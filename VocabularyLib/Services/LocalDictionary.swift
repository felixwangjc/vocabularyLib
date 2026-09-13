import Foundation
import SQLite3

/// Called only from DictionaryService's actor. No network or full-table loading.
struct LocalDictionary {
    var databaseURL: URL? = Bundle.main.url(forResource: "ecdict", withExtension: "sqlite")
    var examplesURL: URL? = Bundle.main.url(forResource: "examples", withExtension: "sqlite")

    func example(for word: String) -> String? {
        guard let examplesURL else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(examplesURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT sentence FROM examples WHERE word = ? COLLATE NOCASE LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, word, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    func lookup(_ word: String) -> WordEntry? {
        guard let databaseURL else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT phonetic, english, chinese FROM words WHERE word = ? COLLATE NOCASE LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, word, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }
        func column(_ index: Int32) -> String {
            guard let text = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: text)
        }
        let english = column(1)
        let chinese = column(2)
        return WordEntry(word: word, phonetic: column(0),
                         chineseDefinition: chinese.isEmpty ? "暂无中文释义" : chinese,
                         englishDefinition: english.isEmpty ? "暂无英文释义" : english,
                         example: "")
    }
}
