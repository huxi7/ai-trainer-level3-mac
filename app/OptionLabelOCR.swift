/**
 * [INPUT]: 依赖 CoreImage 增强彩色按钮；依赖 Vision 读取按钮图像拼接条。
 * [OUTPUT]: OptionLetter 与 OptionLabelOCR.letters；返回实际读到的字母位置。
 * [POS]: app 的选项字母补读器；不读取答案，不按题库顺序补字母。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit
import CoreImage
import Vision

struct OptionLetter {
    let letter: String
    let box: CGRect
}

enum OptionLabelOCR {
    private static let context = CIContext()

    static func letters(in image: CGImage) throws -> [OptionLetter] {
        let rectangles = buttons(in: image)
        guard rectangles.count >= 2 else { return [] }
        let matrix = CIFilter(name: "CIColorMatrix")!
        matrix.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        let contrast = CIVector(x: 3.5, y: 0, z: -3.5, w: 0)
        for key in ["inputRVector", "inputGVector", "inputBVector"] {
            matrix.setValue(contrast, forKey: key)
        }
        guard let filtered = matrix.outputImage,
              let enhanced = context.createCGImage(filtered, from: filtered.extent) else { return [] }
        // --- Vision 会忽略孤立字母；拼接实际按钮图像，按图像槽位映射回原图 ---
        let slot: CGFloat = 100, stripHeight: CGFloat = 180
        let width = Int(slot) * rectangles.count, height = Int(stripHeight)
        guard let canvas = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        canvas.setFillColor(NSColor.white.cgColor)
        canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
        canvas.interpolationQuality = .high
        var regions: [(crop: CGRect, target: CGRect)] = []
        for (index, rectangle) in rectangles.enumerated() {
            let cropWidth = rectangle.width * 0.40
            let cropHeight = min(rectangle.height * 0.75, rectangle.width * 0.55)
            let crop = CGRect(x: rectangle.midX - cropWidth / 2, y: rectangle.midY - cropHeight / 2,
                              width: cropWidth, height: cropHeight).integral
            guard let button = enhanced.cropping(to: crop) else { return [] }
            let drawHeight = slot * crop.height / crop.width
            let target = CGRect(x: CGFloat(index) * slot, y: (stripHeight - drawHeight) / 2,
                                width: slot, height: drawHeight)
            canvas.draw(button, in: target)
            regions.append((crop, target))
        }
        guard let strip = canvas.makeImage() else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: strip).perform([request])
        var letters: [OptionLetter] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.uppercased().filter { !$0.isWhitespace }
            guard text.range(of: "^[A-H]+$", options: .regularExpression) != nil else { continue }
            let box = observation.boundingBox
            let first = max(0, Int(box.minX * CGFloat(width) / slot))
            let last = min(regions.count - 1, Int(box.maxX * CGFloat(width) / slot))
            guard first <= last, text.count == last - first + 1 else { continue }
            for (offset, character) in text.enumerated() {
                let rectangle = rectangles[first + offset]
                let characterHeight = min(rectangle.height * 0.50, rectangle.width * 0.30)
                let pixelBox = CGRect(x: rectangle.midX - characterHeight * 0.40,
                                      y: rectangle.midY - characterHeight / 2,
                                      width: characterHeight * 0.80, height: characterHeight)
                letters.append(OptionLetter(letter: String(character), box: pixelBox))
            }
        }
        return letters
    }

    private struct ButtonRun {
        var frame: CGRect
        var lastY: Int
    }

    private static func buttons(in image: CGImage) -> [CGRect] {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let minimumWidth = max(16, width / 180), maximumWidth = max(120, width / 12)
        var runs: [ButtonRun] = []
        pixels.withUnsafeMutableBytes { buffer in
            guard let bitmap = CGContext(data: buffer.baseAddress, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                             CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            func isGold(_ x: Int, _ y: Int) -> Bool {
                let index = (y * width + x) * 4
                return bytes[index] > 180 && bytes[index + 1] > 90 &&
                    Int(bytes[index]) - Int(bytes[index + 2]) > 110
            }
            for y in stride(from: 0, to: height, by: 2) {
                var x = 0
                while x < width {
                    if !isGold(x, y) { x += 1; continue }
                    let start = x
                    while x < width, isGold(x, y) { x += 1 }
                    let length = x - start
                    guard length >= 4, length <= maximumWidth else { continue }
                    let segment = CGRect(x: start, y: y, width: length, height: 2)
                    if let index = runs.indices.last(where: {
                        y - runs[$0].lastY <= 4 && segment.minX <= runs[$0].frame.maxX &&
                            segment.maxX >= runs[$0].frame.minX
                    }) {
                        runs[index].frame = runs[index].frame.union(segment)
                        runs[index].lastY = y
                    } else if length >= minimumWidth {
                        runs.append(ButtonRun(frame: segment, lastY: y))
                    }
                }
            }
        }
        var candidates: [CGRect] = []
        for run in runs {
            let box = run.frame
            let ratio = box.width / box.height
            let correctWidth = box.width >= CGFloat(minimumWidth) && box.width <= CGFloat(maximumWidth)
            let correctHeight = box.height >= 18 && box.height < CGFloat(height) * 0.18
            if correctWidth && correctHeight && ratio >= 0.8 && ratio <= 3.2 {
                candidates.append(box)
            }
        }
        // --- 至少两个按钮共用字母列，排除菜单图标和独立装饰 ---
        var aligned: [CGRect] = []
        for box in candidates {
            let hasNeighbour = candidates.contains { other -> Bool in
                let sameColumn = abs(other.midX - box.midX) < max(box.width, other.width) * 0.25
                let sameWidth = abs(other.width - box.width) < max(box.width, other.width) * 0.10
                return other != box && sameColumn && sameWidth
            }
            if hasNeighbour { aligned.append(box) }
        }
        return aligned.sorted { $0.minY < $1.minY }
    }
}
