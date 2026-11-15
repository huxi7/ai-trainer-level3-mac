/**
 * [INPUT]: 依赖 AppKit 绘制菜单滑块；依赖 UserDefaults 保存浮字外观。
 * [OUTPUT]: FloatingTextStyle 与 AppearanceMenuView；滑动时通知入口预览。
 * [POS]: app 的外观设置；只调整答案浮字，不改变识别结果。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit

struct FloatingTextStyle {
    static let sizeRange = 8.0...32.0
    static let transparencyRange = 0.0...95.0
    private static let sizeKey = "answerFontSize"
    private static let transparencyKey = "answerTransparency"

    var fontSize: Double
    var transparency: Double
    var font: NSFont { .systemFont(ofSize: CGFloat(fontSize), weight: .ultraLight) }
    var opacity: CGFloat { CGFloat(1 - transparency / 100) }

    static func load() -> FloatingTextStyle {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [sizeKey: 9.0, transparencyKey: 85.0])
        return FloatingTextStyle(
            fontSize: min(sizeRange.upperBound, max(sizeRange.lowerBound, defaults.double(forKey: sizeKey))),
            transparency: min(transparencyRange.upperBound, max(transparencyRange.lowerBound,
                                                               defaults.double(forKey: transparencyKey)))
        )
    }

    func save() {
        UserDefaults.standard.set(fontSize, forKey: Self.sizeKey)
        UserDefaults.standard.set(transparency, forKey: Self.transparencyKey)
    }
}

final class AppearanceMenuView: NSView {
    private var style: FloatingTextStyle
    private let onChange: (FloatingTextStyle) -> Void
    private let sizeLabel = NSTextField(labelWithString: "")
    private let transparencyLabel = NSTextField(labelWithString: "")

    init(style: FloatingTextStyle, onChange: @escaping (FloatingTextStyle) -> Void) {
        self.style = style
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 236, height: 128))
        addControl(label: sizeLabel, y: 88, value: style.fontSize,
                   range: FloatingTextStyle.sizeRange, action: #selector(changeSize))
        addControl(label: transparencyLabel, y: 32, value: style.transparency,
                   range: FloatingTextStyle.transparencyRange, action: #selector(changeTransparency))
        updateLabels()
    }

    required init?(coder: NSCoder) { fatalError("仅使用代码创建外观菜单") }

    private func addControl(label: NSTextField, y: CGFloat, value: Double,
                            range: ClosedRange<Double>, action: Selector) {
        label.frame = NSRect(x: 16, y: y, width: 204, height: 20)
        label.font = .systemFont(ofSize: 12)
        addSubview(label)
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: self, action: action)
        slider.frame = NSRect(x: 16, y: y - 24, width: 204, height: 22)
        slider.isContinuous = true
        slider.setAccessibilityLabel(label === sizeLabel ? "答案字号" : "答案透明度")
        addSubview(slider)
    }

    private func updateLabels() {
        sizeLabel.stringValue = "字号：\(Int(style.fontSize)) pt"
        transparencyLabel.stringValue = "透明度：\(Int(style.transparency))%"
    }

    private func didChange() {
        style.save()
        updateLabels()
        onChange(style)
    }

    @objc private func changeSize(_ sender: NSSlider) {
        style.fontSize = sender.doubleValue.rounded()
        didChange()
    }

    @objc private func changeTransparency(_ sender: NSSlider) {
        style.transparency = sender.doubleValue.rounded()
        didChange()
    }
}
