/**
 * [INPUT]: 依赖截图、OCR、Matcher、外观及匹配设置；监听右键。
 * [OUTPUT]: 按设定时长显示透明答案；提供匹配度、诊断截图与设置菜单。
 * [POS]: app 的交互入口；所有 AppKit 窗口操作回到主线程。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit
import ApplicationServices

final class AssistantDelegate: NSObject, NSApplicationDelegate {
    private var questions: [Question] = []
    private var item: NSStatusItem?
    private var monitor: Any?
    private var panel: NSPanel?
    private var enabled = true
    private var captureMode: CaptureMode = .frontWindow
    private var textStyle = FloatingTextStyle.load()
    private var matchingSettings = MatchingSettings.load()
    private var lastReport: MatchReport?
    private var lastPoint: NSPoint?
    private var lastCheckItem: NSMenuItem?
    private var busy = false
    private var lastClick = Date.distantPast
    private var displayNumber = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { questions = try Bank.load() }
        catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.title = "答"
        refreshMenu()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let point = NSEvent.mouseLocation
            let windowID = event.windowNumber > 0 ? CGWindowID(event.windowNumber) : nil
            DispatchQueue.main.async { self?.rightClicked(at: point, windowID: windowID) }
        }
        NSLog("三级解题助手启动；屏幕录制=%d，输入监听=%d", CGPreflightScreenCaptureAccess(), CGPreflightListenEventAccess())
        let screen = NSScreen.main?.visibleFrame ?? .zero
        showMessage("应用启动", at: NSPoint(x: screen.maxX - 120, y: screen.maxY - 8), duration: 4,
                    startup: true)
    }

    private func refreshMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: enabled ? "右键识别：开" : "右键识别：关", action: #selector(toggle), keyEquivalent: ""))
        let front = NSMenuItem(title: "截取前台窗口", action: #selector(useFrontWindow), keyEquivalent: "")
        front.state = captureMode == .frontWindow ? .on : .off
        menu.addItem(front)
        let display = NSMenuItem(title: "截取整个屏幕", action: #selector(useDisplay), keyEquivalent: "")
        display.state = captureMode == .display ? .on : .off
        menu.addItem(display)
        let appearance = NSMenuItem(title: "浮字设置", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        let controls = NSMenuItem()
        controls.view = AppearanceMenuView(style: textStyle) { [weak self] style in
            guard let self = self else { return }
            self.textStyle = style
            let point = NSEvent.mouseLocation
            self.showMessage("A", at: NSPoint(x: point.x + 80, y: point.y + 25))
        }
        appearanceMenu.addItem(controls)
        appearance.submenu = appearanceMenu
        menu.addItem(appearance)
        let matching = NSMenuItem(title: "匹配设置", action: nil, keyEquivalent: "")
        let matchingMenu = NSMenu()
        let matchingControls = NSMenuItem()
        matchingControls.view = MatchingMenuView(settings: matchingSettings) { [weak self] settings in
            guard let self = self else { return }
            self.matchingSettings = settings
            if let report = self.lastReport, let point = self.lastPoint, self.panel?.isVisible == true {
                self.show(report.shortDisplay(showScore: settings.showScore), at: point)
            }
        }
        matchingMenu.addItem(matchingControls)
        let explanation = NSMenuItem(title: "匹配度怎么算？", action: #selector(explainMatching), keyEquivalent: "")
        explanation.target = self
        matchingMenu.addItem(explanation)
        matching.submenu = matchingMenu
        menu.addItem(matching)
        let lastCheck = NSMenuItem(title: lastReport?.summary ?? "尚未识别题目", action: nil, keyEquivalent: "")
        menu.addItem(lastCheck)
        lastCheckItem = lastCheck
        menu.addItem(NSMenuItem(title: "检查权限", action: #selector(checkPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item?.menu = menu
    }

    @objc private func toggle() {
        enabled.toggle()
        refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func useFrontWindow() { captureMode = .frontWindow; refreshMenu() }

    @objc private func useDisplay() { captureMode = .display; refreshMenu() }

    @objc private func explainMatching() {
        let alert = NSAlert()
        alert.messageText = "匹配度怎么算？"
        alert.informativeText = "先把截图转成文字，再与题库的题干和全部选项比较。增字、漏字、错字都会扣分；长文本也比较相邻字符。\n\n显示的百分比取题干和所有选项中最低的一项。例如题干 92%、最弱选项 68%，显示 68%；阈值设为 60% 就可出答案。\n\n答案来自题库的答案内容，再映射到当前页面字母。数字或否定词不同、缺少整项、多个答案接近时显示“无”。\n\n默认阈值 60%；越低越容易出答案，也更容易误匹配。匹配度是文字相似度，不是答对概率。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func checkPermissions() {
        let screen = CGPreflightScreenCaptureAccess() ? "已允许" : "未允许"
        let input = CGPreflightListenEventAccess() ? "已允许" : "未允许"
        let alert = NSAlert()
        alert.messageText = "权限状态"
        alert.informativeText = "屏幕录制：\(screen)\n输入监听：\(input)"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func rightClicked(at point: NSPoint, windowID: CGWindowID?) {
        guard enabled, !busy, Date().timeIntervalSince(lastClick) > 0.7 else { return }
        NSLog("收到右键事件；窗口=%u", windowID ?? 0)
        busy = true
        lastClick = Date()
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            let alert = NSAlert()
            alert.messageText = "请允许助手录制屏幕"
            alert.informativeText = "在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中，允许“三级解题助手”，然后重新启动助手。若开关已经打开，请关闭后重新打开。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "知道了")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            busy = false
            return
        }
        let settings = matchingSettings
        let mode = captureMode
        Task {
            let answer: String
            do {
                let image = try await Capture.screen(at: point, mode: mode, preferredWindowID: windowID)
                let rows = try OCR.rows(from: image)
                let report = Matcher.inspect(rows, in: questions, minimumSimilarity: settings.minimumSimilarity)
                answer = report.shortDisplay(showScore: settings.showScore)
                NSLog("匹配状态：%@", report.summary)
                await MainActor.run {
                    lastReport = report
                    lastPoint = point
                    lastCheckItem?.title = report.summary
                }
                if report.result == nil {
                    NSLog("未匹配；文字行=%d；OCR=%@", rows.count, rows.prefix(20).map(\.text).joined(separator: " | "))
                }
            } catch {
                NSLog("截图或识别失败：%@", String(describing: error))
                answer = "无"
                await MainActor.run {
                    lastReport = MatchReport(result: nil, score: nil, reason: "截图或 OCR 失败")
                    lastCheckItem?.title = "截图或 OCR 失败"
                }
            }
            NSLog("识别结束：%@", answer)
            await MainActor.run {
                show(answer, at: point)
                busy = false
            }
        }
    }

    private func show(_ answer: String, at point: NSPoint) {
        showMessage(answer, at: point)
    }

    private func showMessage(_ message: String, at point: NSPoint, duration: TimeInterval? = nil,
                             startup: Bool = false) {
        panel?.orderOut(nil)
        let font = startup ? NSFont.systemFont(ofSize: 14, weight: .regular) : textStyle.font
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let width = ceil(textSize.width) + 8
        let height = ceil(textSize.height) + 4
        let frame = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(x: max(frame.minX, min(point.x + 12, frame.maxX - width)),
                             y: max(frame.minY, min(point.y + 12, frame.maxY - height)))
        let window = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let label = NSTextField(labelWithString: message)
        label.frame = NSRect(x: 2, y: 2, width: width - 4, height: height - 4)
        label.drawsBackground = false
        label.isBezeled = false
        label.font = font
        label.textColor = NSColor.systemOrange.withAlphaComponent(startup ? 0.9 : textStyle.opacity)
        content.addSubview(label)
        window.contentView = content
        window.orderFrontRegardless()
        panel = window
        displayNumber += 1
        let shown = displayNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + (duration ?? textStyle.displayDuration)) { [weak self] in
            if self?.displayNumber == shown { self?.panel?.orderOut(nil) }
        }
    }
}

@main enum EntryPoint {
    static func main() {
        if (3...5).contains(CommandLine.arguments.count), CommandLine.arguments[1] == "--check-live" {
            let mode: CaptureMode = CommandLine.arguments[2] == "screen" ? .display : .frontWindow
            let preferredID = CommandLine.arguments.count >= 4 ? CGWindowID(CommandLine.arguments[3]) : nil
            Task {
                do {
                    let image = try await Capture.screen(at: NSEvent.mouseLocation, mode: mode, preferredWindowID: preferredID)
                    if CommandLine.arguments.count == 5 {
                        let url = URL(fileURLWithPath: CommandLine.arguments[4])
                        if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                            CGImageDestinationAddImage(destination, image, nil)
                            _ = CGImageDestinationFinalize(destination)
                        }
                    }
                    let rows = try OCR.rows(from: image)
                    for row in rows.prefix(20) { print(row.text) }
                    let report = Matcher.inspect(rows, in: try Bank.load())
                    print("匹配：\(report.shortDisplay(showScore: true))")
                    print("依据：\(report.summary)")
                    exit(0)
                } catch { fputs("实时检查失败：\(error)\n", stderr); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--permissions" {
            print("屏幕录制：\(CGPreflightScreenCaptureAccess() ? "已允许" : "未允许")")
            print("输入监听：\(CGPreflightListenEventAccess() ? "已允许" : "未允许")")
            return
        }
        if (3...4).contains(CommandLine.arguments.count), CommandLine.arguments[1] == "--check-image" {
            do {
                guard let image = OCR.image(at: CommandLine.arguments[2]) else { throw NSError(domain: "OCR", code: 1) }
                let rows = try OCR.rows(from: image)
                for row in rows { print(String(format: "%.3f %@", row.y, row.text)) }
                let threshold = CommandLine.arguments.count == 4 ? (Double(CommandLine.arguments[3]) ?? 60) / 100 : 0.60
                let report = Matcher.inspect(rows, in: try Bank.load(), minimumSimilarity: threshold)
                print("匹配：\(report.shortDisplay(showScore: true))")
                print("依据：\(report.summary)")
            } catch { fputs("检查失败：\(error)\n", stderr); exit(1) }
            return
        }
        if (3...4).contains(CommandLine.arguments.count), CommandLine.arguments[1] == "--check-text" {
            do {
                let lines = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).split(separator: "\n")
                let rows = lines.enumerated().map { ScreenRow(text: String($0.element), y: Double($0.offset) / Double(lines.count)) }
                let threshold = CommandLine.arguments.count == 4 ? (Double(CommandLine.arguments[3]) ?? 60) / 100 : 0.60
                let report = Matcher.inspect(rows, in: try Bank.load(), minimumSimilarity: threshold)
                print("匹配：\(report.shortDisplay(showScore: true))")
                print("依据：\(report.summary)")
            } catch { fputs("检查失败：\(error)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AssistantDelegate()
        app.delegate = delegate
        app.run()
    }
}
