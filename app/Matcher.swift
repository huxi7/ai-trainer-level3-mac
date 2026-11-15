/**
 * [INPUT]: 依赖 OCR 的 ScreenRow、Bank 的题目与调用方的匹配阈值。
 * [OUTPUT]: MatchReport 输出答案、最低文字匹配度和拒绝原因。
 * [POS]: app 的判题边界；用字符编辑距离容错，按答案内容映射页面字母。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation

struct MatchResult {
    let id: String
    let letters: [String]
    let contents: [String]
    let isJudgement: Bool

    var display: String {
        isJudgement ? contents.joined(separator: "；") : "\(letters.joined(separator: "、"))  \(contents.joined(separator: "；"))"
    }

    var shortDisplay: String {
        isJudgement ? contents.joined(separator: "、") : letters.joined(separator: "、")
    }
}

struct MatchReport {
    let result: MatchResult?
    let score: Double?
    let reason: String

    var percent: Int? { score.map { Int(floor($0 * 100 + 0.000001)) } }

    func shortDisplay(showScore: Bool) -> String {
        let answer = result?.shortDisplay ?? "无"
        guard showScore, let percent else { return answer }
        return "\(answer)  \(percent)%"
    }

    var summary: String {
        if let percent { return "\(reason)（最低匹配度 \(percent)%）" }
        return reason
    }
}

private struct StemHit {
    let question: Question
    let score: Double
    let end: Int
}

enum Matcher {
    private static let labelPattern = try! NSRegularExpression(pattern: "^\\s*[^\\p{L}\\p{N}]{0,3}\\s*([A-H])(?:[\\s.．、:：)）]+|(?=[\\p{Han}])|$)(.*)$")
    private static let nextPattern = try! NSRegularExpression(pattern: "^\\s*[0-9]{1,4}[、.．]")
    private static let numberPattern = try! NSRegularExpression(pattern: "[0-9]+(?:[.．][0-9]+)?%?")

    static func match(_ rows: [ScreenRow], in questions: [Question],
                      minimumSimilarity: Double = 0.60) -> MatchResult? {
        inspect(rows, in: questions, minimumSimilarity: minimumSimilarity).result
    }

    static func inspect(_ rows: [ScreenRow], in questions: [Question],
                        minimumSimilarity: Double = 0.60) -> MatchReport {
        let threshold = min(0.95, max(0.40, minimumSimilarity))
        // --- 先找选项首行；题干必须在此之前完整结束 ---
        let windows = rows.indices.flatMap { end -> [(String, Int)] in
            guard end + 1 < rows.count, isChoice(rows[end + 1].text) else { return [] }
            var candidates: [(String, Int)] = []
            var text = ""
            for start in stride(from: end, through: max(0, end - 19), by: -1) {
                if isChoice(rows[start].text) || isBoundary(rows[start].text) { break }
                text = cleanStem(rows[start].text) + text
                if normal(text).count >= 6 { candidates.append((text, end)) }
            }
            return candidates
        }
        guard !windows.isEmpty else {
            return MatchReport(result: nil, score: nil, reason: "未识别到题干和选项字母")
        }
        let screenText = normal(rows.map(\.text).joined())
        let screenCharacters = Set(screenText)
        let shortlist = questions.filter { question in
            let stem = normal(question.stem)
            return stem.count >= 6 &&
                Double(stem.filter { screenCharacters.contains($0) }.count) / Double(stem.count) >= 0.40
        }
        var hits: [StemHit] = []
        for question in shortlist {
            if let best = windows.map({ (similarity(question.stem, $0.0), $0.1) }).max(by: { $0.0 < $1.0 }), best.0 >= 0.40 {
                hits.append(StemHit(question: question, score: best.0, end: best.1))
            }
        }
        hits.sort { $0.score > $1.score }
        guard !hits.isEmpty else {
            return MatchReport(result: nil, score: nil, reason: "未找到接近的题干，或关键数字／否定词不一致")
        }
        var candidates: [(result: MatchResult, score: Double, rank: Double, ambiguous: Bool)] = []
        var failure = "选项缺失或字母未识别"
        for hit in hits.prefix(32) {
            if hit.question.conflict { failure = "题库答案冲突"; continue }
            guard let screenOptions = options(after: hit.end, rows: rows, judgement: hit.question.type == 3),
                  screenOptions.count == hit.question.options.count else { continue }
            var answerKeys: [String] = []
            for content in hit.question.answers {
                let matches = hit.question.options.filter { normal($0.value) == normal(content) }
                guard matches.count == 1 else {
                    answerKeys = []
                    break
                }
                answerKeys.append(matches.first!.key)
            }
            guard answerKeys.count == hit.question.answers.count, !answerKeys.isEmpty else {
                failure = "题库答案内容不明确"; continue
            }
            guard let assignment = assign(hit.question.options, to: screenOptions, answerKeys: answerKeys) else {
                failure = "选项内容差异过大，或关键数字／否定词不一致"; continue
            }
            let letters = answerKeys.compactMap { assignment.mapping[$0]?.letter }.sorted()
            guard letters.count == answerKeys.count else { continue }
            let result = MatchResult(id: hit.question.id, letters: letters,
                                     contents: hit.question.answers, isJudgement: hit.question.type == 3)
            let scores = assignment.mapping.values.map(\.score)
            let score = min(hit.score, scores.min() ?? 0)
            let rank = 0.55 * hit.score + 0.45 * scores.reduce(0, +) / Double(scores.count)
            candidates.append((result, score, rank, assignment.ambiguous))
        }
        candidates.sort { $0.rank > $1.rank }
        guard let best = candidates.first else {
            return MatchReport(result: nil, score: nil, reason: failure)
        }
        let otherAnswer = candidates.dropFirst().contains {
            best.rank - $0.rank < 0.04 &&
                ($0.result.shortDisplay != best.result.shortDisplay ||
                 Set($0.result.contents.map(normal)) != Set(best.result.contents.map(normal)))
        }
        if best.ambiguous || otherAnswer {
            return MatchReport(result: nil, score: best.score, reason: "多个答案接近，无法明确区分")
        }
        guard best.score >= threshold else {
            return MatchReport(result: nil, score: best.score, reason: "低于当前阈值 \(Int(threshold * 100))%")
        }
        return MatchReport(result: best.result, score: best.score, reason: "已匹配")
    }

    private struct Assigned {
        let letter: String
        let score: Double
    }

    private struct Assignment {
        let mapping: [String: Assigned]
        let ambiguous: Bool
    }

    private static func assign(_ source: [String: String], to screen: [String: String],
                               answerKeys: [String]) -> Assignment? {
        let sourceKeys = source.keys.sorted()
        let screenKeys = screen.keys.sorted()
        let scores = Dictionary(uniqueKeysWithValues: sourceKeys.map { original in
            (original, Dictionary(uniqueKeysWithValues: screenKeys.map { current in
                (current, similarity(source[original]!, screen[current]!))
            }))
        })
        var ranked: [(Double, [String: Assigned])] = []
        func visit(_ index: Int, _ used: Set<String>, _ mapping: [String: Assigned], _ total: Double) {
            if index == sourceKeys.count {
                ranked.append((total, mapping))
                return
            }
            let original = sourceKeys[index]
            for current in screenKeys where !used.contains(current) {
                let score = scores[original]![current]!
                if score < 0.40 { continue }
                var next = mapping
                next[original] = Assigned(letter: current, score: score)
                visit(index + 1, used.union([current]), next, total + score)
            }
        }
        visit(0, [], [:], 0)
        ranked.sort { $0.0 > $1.0 }
        guard let best = ranked.first else { return nil }
        let answers = Set(answerKeys.compactMap { best.1[$0]?.letter })
        let ambiguous = ranked.dropFirst().contains { candidate in
            best.0 - candidate.0 < 0.12 && Set(answerKeys.compactMap { candidate.1[$0]?.letter }) != answers
        }
        return Assignment(mapping: best.1, ambiguous: ambiguous)
    }

    private static func options(after end: Int, rows: [ScreenRow], judgement: Bool) -> [String: String]? {
        guard end + 1 < rows.count else { return nil }
        var found: [String: String] = [:]
        var last: String?
        for row in rows[(end + 1)...] {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if isBoundary(text) ||
                (last != nil && nextPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil) { break }
            if judgement {
                for value in judgementChoices(text) { found[value] = value }
                if found.count == 2 { return found }
                continue
            }
            if let choice = labelledChoice(text) {
                if found[choice.letter] != nil { return nil }
                found[choice.letter] = choice.content
                last = choice.letter
            } else if let last, !text.isEmpty {
                found[last, default: ""] += " " + text
            }
        }
        return found.isEmpty || found.values.contains(where: { normal($0).isEmpty }) ? nil : found
    }

    private static func labelledChoice(_ text: String) -> (letter: String, content: String)? {
        guard let match = labelPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let label = Range(match.range(at: 1), in: text),
              let content = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[label]), String(text[content]))
    }

    private static func judgementChoices(_ text: String) -> [String] {
        let value = labelledChoice(text)?.content ?? text
        let cleaned = String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        switch cleaned {
        case "正确", "对", "true": return ["正确"]
        case "错误", "错", "false": return ["错误"]
        case "正确错误", "错误正确": return ["正确", "错误"]
        default: return []
        }
    }

    private static func isChoice(_ text: String) -> Bool {
        labelledChoice(text) != nil || !judgementChoices(text).isEmpty
    }

    private static func isBoundary(_ text: String) -> Bool {
        let value = normal(text)
        return value.hasPrefix("答案") || value.hasPrefix("營案") || value.contains("试题解析") ||
            value == "确定" || value.hasPrefix("暂存") || value.hasPrefix("暫存") ||
            value.contains("交卷") || value.contains("答题卡") || value.hasPrefix("判断题") ||
            value.hasPrefix("多选题") || value.hasPrefix("单选题") || value.hasPrefix("単选题")
    }

    private static func cleanStem(_ text: String) -> String {
        nextPattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                             withTemplate: "")
    }

    private static func normal(_ text: String) -> String {
        let significant = CharacterSet(charactersIn: "+-=<>%×÷≤≥≠")
        return String(text.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || significant.contains($0)
        })
    }

    private static func grams(_ text: String) -> Set<String> {
        let chars = Array(text)
        if chars.count < 2 { return [text] }
        return Set((0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) })
    }

    private static func similarity(_ original: String, _ observed: String) -> Double {
        let a = normal(original), b = normal(observed)
        if a.isEmpty || b.isEmpty { return 0 }
        // --- 数字、否定词与运算符不能用模糊分数掩盖 ---
        func numbers(_ value: String) -> [String] {
            let text = value.precomposedStringWithCompatibilityMapping
            return numberPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }
        }
        guard numbers(original) == numbers(observed) else { return 0 }
        if a == b { return 1 }
        for marker in "不未非无+-=<>%×÷≤≥≠" {
            guard a.filter({ $0 == marker }).count == b.filter({ $0 == marker }).count else { return 0 }
        }
        let left = grams(a), right = grams(b)
        let dice = 2 * Double(left.intersection(right).count) / Double(left.count + right.count)
        let source = Array(a), target = Array(b)
        var previous = Array(0...target.count)
        for i in source.indices {
            var current = [i + 1]
            for j in target.indices {
                current.append(min(current[j] + 1, previous[j + 1] + 1,
                                   previous[j] + (source[i] == target[j] ? 0 : 1)))
            }
            previous = current
        }
        let edit = 1 - Double(previous[target.count]) / Double(max(source.count, target.count))
        // --- 短选项以字符为准；长文本兼看相邻字符，保留顺序信息 ---
        return max(source.count, target.count) <= 6 ? edit : 0.80 * edit + 0.20 * dice
    }
}
