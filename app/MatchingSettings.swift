/**
 * [INPUT]: 依赖 AppKit 的菜单控件和 UserDefaults 的本地设置。
 * [OUTPUT]: MatchingSettings 与 MatchingMenuView；保存阈值和匹配度开关。
 * [POS]: app 的匹配设置；阈值交给 Matcher，显示开关交给入口。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit

struct MatchingSettings {
    static let thresholdRange = 40.0...95.0
    static let defaultThreshold = 60.0
    private static let thresholdKey = "minimumTextSimilarity"
    private static let scoreKey = "showTextSimilarity"

    var thresholdPercent: Double
    var showScore: Bool
    var minimumSimilarity: Double { thresholdPercent / 100 }

    static func load() -> MatchingSettings {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [thresholdKey: defaultThreshold, scoreKey: true])
        return MatchingSettings(
            thresholdPercent: min(thresholdRange.upperBound,
                                  max(thresholdRange.lowerBound, defaults.double(forKey: thresholdKey))),
            showScore: defaults.bool(forKey: scoreKey)
        )
    }

    func save() {
        UserDefaults.standard.set(thresholdPercent, forKey: Self.thresholdKey)
        UserDefaults.standard.set(showScore, forKey: Self.scoreKey)
    }
}

final class MatchingMenuView: NSView {
    private var settings: MatchingSettings
    private let onChange: (MatchingSettings) -> Void
    private let thresholdLabel = NSTextField(labelWithString: "")
    private let scoreToggle = NSButton(checkboxWithTitle: "显示匹配度", target: nil, action: nil)

    init(settings: MatchingSettings, onChange: @escaping (MatchingSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 270, height: 150))
        thresholdLabel.frame = NSRect(x: 16, y: 116, width: 238, height: 20)
        thresholdLabel.font = .systemFont(ofSize: 12)
        addSubview(thresholdLabel)

        let slider = NSSlider(value: settings.thresholdPercent,
                              minValue: MatchingSettings.thresholdRange.lowerBound,
                              maxValue: MatchingSettings.thresholdRange.upperBound,
                              target: self, action: #selector(changeThreshold))
        slider.frame = NSRect(x: 16, y: 89, width: 238, height: 22)
        slider.isContinuous = true
        slider.setAccessibilityLabel("最低匹配度")
        addSubview(slider)

        let hint = NSTextField(labelWithString: "越低越容易出答案；默认 60%")
        hint.frame = NSRect(x: 16, y: 65, width: 238, height: 20)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        addSubview(hint)

        scoreToggle.frame = NSRect(x: 16, y: 38, width: 238, height: 22)
        scoreToggle.font = .systemFont(ofSize: 12)
        scoreToggle.target = self
        scoreToggle.action = #selector(toggleScore)
        scoreToggle.state = settings.showScore ? .on : .off
        addSubview(scoreToggle)

        let description = NSTextField(labelWithString: "文字相似度，不是答对概率")
        description.frame = NSRect(x: 16, y: 12, width: 238, height: 20)
        description.font = .systemFont(ofSize: 11)
        description.textColor = .secondaryLabelColor
        addSubview(description)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("仅使用代码创建匹配菜单") }

    private func updateLabel() {
        thresholdLabel.stringValue = "最低匹配度：\(Int(settings.thresholdPercent))%"
    }

    private func didChange() {
        settings.save()
        updateLabel()
        onChange(settings)
    }

    @objc private func changeThreshold(_ sender: NSSlider) {
        settings.thresholdPercent = sender.doubleValue.rounded()
        didChange()
    }

    @objc private func toggleScore(_ sender: NSButton) {
        settings.showScore = sender.state == .on
        didChange()
    }
}
