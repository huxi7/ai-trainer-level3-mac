/**
 * [INPUT]: 依赖 AppKit 绘制菜单滑块；依赖 UserDefaults 保存外观和显示时长。
 * [OUTPUT]: 浮字外观与 0.1–3 秒显示时长；滑动时通知入口预览。
 * [POS]: app 的外观设置；只调整答案浮字，不改变识别结果。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit

struct FloatingTextStyle {
    static let sizeRange = 8.0...32.0
    static let transparencyRange = 0.0...95.0
    static let durationRange = 0.1...3.0
    private static let sizeKey = "answerFontSize"
    private static let transparencyKey = "answerTransparency"
    private static let durationKey = "answerDisplayDuration"

    var fontSize: Double
    var transparency: Double
    var displayDuration: TimeInterval
    var font: NSFont { .systemFont(ofSize: CGFloat(fontSize), weight: .ultraLight) }
    var opacity: CGFloat { CGFloat(1 - transparency / 100) }

    static func load() -> FloatingTextStyle {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [sizeKey: 9.0, transparencyKey: 85.0, durationKey: 2.5])
        return FloatingTextStyle(
            fontSize: min(sizeRange.upperBound, max(sizeRange.lowerBound, defaults.double(forKey: sizeKey))),
            transparency: min(transparencyRange.upperBound, max(transparencyRange.lowerBound,
                                                               defaults.double(forKey: transparencyKey))),
            displayDuration: min(durationRange.upperBound, max(durationRange.lowerBound,
                                                               defaults.double(forKey: durationKey)))
        )
    }

    func save() {
        UserDefaults.standard.set(fontSize, forKey: Self.sizeKey)
        UserDefaults.standard.set(transparency, forKey: Self.transparencyKey)
        UserDefaults.standard.set(displayDuration, forKey: Self.durationKey)
    }
}

final class AppearanceMenuView: NSView {
    private var style: FloatingTextStyle
    private let onChange: (FloatingTextStyle) -> Void
    private let sizeLabel = NSTextField(labelWithString: "")
    private let transparencyLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")

    init(style: FloatingTextStyle, onChange: @escaping (FloatingTextStyle) -> Void) {
        self.style = style
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 236, height: 184))
        addControl(label: sizeLabel, y: 144, value: style.fontSize,
                   range: FloatingTextStyle.sizeRange, action: #selector(changeSize))
        addControl(label: transparencyLabel, y: 88, value: style.transparency,
                   range: FloatingTextStyle.transparencyRange, action: #selector(changeTransparency))
        addControl(label: durationLabel, y: 32, value: style.displayDuration,
                   range: FloatingTextStyle.durationRange, action: #selector(changeDuration))
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
        let title = label === sizeLabel ? "答案字号" : (label === transparencyLabel ? "答案透明度" : "答案显示时长")
        slider.setAccessibilityLabel(title)
        addSubview(slider)
    }

    private func updateLabels() {
        sizeLabel.stringValue = "字号：\(Int(style.fontSize)) pt"
        transparencyLabel.stringValue = "透明度：\(Int(style.transparency))%"
        durationLabel.stringValue = String(format: "显示时长：%.1f 秒", style.displayDuration)
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

    @objc private func changeDuration(_ sender: NSSlider) {
        style.displayDuration = (sender.doubleValue * 10).rounded() / 10
        didChange()
    }
}
