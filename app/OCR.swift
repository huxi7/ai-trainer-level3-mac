/**
 * [INPUT]: 依赖 Vision 识别正文；依赖 OptionLabelOCR 补读彩色按钮字母。
 * [OUTPUT]: 带位置的 ScreenRow；归位字母并排除题目列外的图标。
 * [POS]: app 的视觉输入边界；正文读原图，按钮增强仅补读字母。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit
import Vision

struct ScreenRow {
    let text: String
    let y: Double
    var x: Double = 0
    var height: Double = 0
}

enum OCR {
    private struct Fragment {
        var text: String
        var y: Double
        let x: Double
        let width: Double
        let height: Double
    }

    static func rows(from image: CGImage) throws -> [ScreenRow] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        var fragments = (request.results ?? []).compactMap { observation -> Fragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return Fragment(text: text, y: 1 - box.midY, x: box.minX,
                            width: box.width, height: box.height)
        }
        // --- 彩色按钮字母与正文分别读取，再按真实位置组合 ---
        let recovered = try OptionLabelOCR.letters(in: image)
        if recovered.count >= 2 {
            let left = (recovered.map { $0.box.minX }.min() ?? 0) / CGFloat(image.width) - 0.02
            let right = (recovered.map { $0.box.maxX }.max() ?? 0) / CGFloat(image.width) + 0.50
            fragments.removeAll { $0.x < left || $0.x > right }
        }
        for label in recovered {
            let x = label.box.minX / CGFloat(image.width)
            let y = label.box.midY / CGFloat(image.height)
            let width = label.box.width / CGFloat(image.width)
            let height = label.box.height / CGFloat(image.height)
            fragments = fragments.compactMap { fragment in
                guard abs(fragment.y - y) <= max(fragment.height, height),
                      fragment.x < x + width, fragment.x + fragment.width >= x - width else { return fragment }
                var revised = fragment
                let text = fragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count <= 3 { return nil }
                let pattern = "^\\s*[^\\p{L}\\p{N}]{0,3}\\s*[A-H0-9](?:[\\s.．、:：)）]+|(?=\\p{Han}))"
                revised.text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                revised = Fragment(text: revised.text, y: fragment.y,
                                   x: max(fragment.x, x + width * 1.2),
                                   width: fragment.width, height: fragment.height)
                return revised.text.isEmpty ? nil : revised
            }
            fragments.append(Fragment(text: label.letter, y: y, x: x, width: width, height: height))
        }
        // --- 选项字母在单元格中居中；先找右侧段落的首行 ---
        let labels = fragments.indices.filter { isOptionLetter(fragments[$0].text) }
        for index in labels {
            let label = fragments[index]
            let content = fragments.filter {
                !isOptionLetter($0.text) && $0.x >= label.x + label.width * 0.8 &&
                $0.x - label.x < 0.15
            }.sorted { $0.y < $1.y }
            guard var line = content.indices.min(by: {
                abs(content[$0].y - label.y) < abs(content[$1].y - label.y)
            }), abs(content[line].y - label.y) <= max(content[line].height, label.height) * 2 else { continue }
            while line > 0 {
                let previous = content[line - 1], current = content[line]
                let gap = current.y - previous.y
                let otherLabel = labels.contains {
                    $0 != index && fragments[$0].y >= previous.y - previous.height / 2 &&
                        fragments[$0].y <= current.y + current.height / 2
                }
                guard gap < max(previous.height, current.height) * 2, !otherLabel else { break }
                line -= 1
            }
            fragments[index].y = content[line].y
        }
        fragments.sort { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        var grouped: [[Fragment]] = []
        for fragment in fragments {
            if let last = grouped.indices.last,
               abs(grouped[last][0].y - fragment.y) < min(grouped[last][0].height, fragment.height) * 0.55 {
                grouped[last].append(fragment)
            } else {
                grouped.append([fragment])
            }
        }
        return grouped.map { row in
            ScreenRow(text: row.sorted { $0.x < $1.x }.map(\.text).joined(separator: " "),
                      y: row[0].y, x: row.map(\.x).min() ?? 0, height: row.map(\.height).max() ?? 0)
        }
    }

    private static func isOptionLetter(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.range(of: "^[^\\p{L}\\p{N}]{0,3}[A-H][.．、:：)）]?$", options: .regularExpression) != nil
    }

    static func image(at path: String) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
