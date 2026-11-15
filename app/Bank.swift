/**
 * [INPUT]: 依赖随应用打包的 questions.sqlite 和 SQLite3。
 * [OUTPUT]: 提供 Question 与 Bank.load()，只读取去重后的题干、选项和答案内容。
 * [POS]: app 的数据边界；来源字母留在记录中，匹配器只用答案内容。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation
import SQLite3

struct Question {
    let id: String
    let type: Int
    let stem: String
    let options: [String: String]
    let answers: [String]
    let conflict: Bool
}

enum Bank {
    static func load() throws -> [Question] {
        guard let path = Bundle.main.url(forResource: "questions", withExtension: "sqlite") else {
            throw NSError(domain: "Bank", code: 1, userInfo: [NSLocalizedDescriptionKey: "题库文件缺失"])
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw NSError(domain: "Bank", code: 2, userInfo: [NSLocalizedDescriptionKey: "题库无法读取"])
        }
        defer { sqlite3_close(db) }
        let sql = "SELECT id, type, stem, options_json, answer_contents_json, answer_conflict FROM questions"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "Bank", code: 3, userInfo: [NSLocalizedDescriptionKey: "题库结构不匹配"])
        }
        defer { sqlite3_finalize(statement) }
        var questions: [Question] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            func value(_ index: Int32) -> String {
                guard let pointer = sqlite3_column_text(statement, index) else { return "" }
                return String(cString: pointer)
            }
            let options = (try? JSONDecoder().decode([String: String].self, from: Data(value(3).utf8))) ?? [:]
            let answers = (try? JSONDecoder().decode([String].self, from: Data(value(4).utf8))) ?? []
            questions.append(Question(id: value(0), type: Int(sqlite3_column_int(statement, 1)),
                                      stem: value(2), options: options,
                                      answers: answers, conflict: sqlite3_column_int(statement, 5) != 0))
        }
        return questions
    }
}
