/**
 * [INPUT]: 依赖 ScreenCaptureKit 的显示器列表及截图接口。
 * [OUTPUT]: 按 CaptureMode 截取右键所在窗口或鼠标所在显示器。
 * [POS]: app 的系统截图边界；窗口模式用事件窗口与屏幕层级定位题目。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit
import ScreenCaptureKit

enum CaptureMode { case frontWindow, display }

@MainActor enum Capture {
    static func screen(at point: NSPoint, mode: CaptureMode, preferredWindowID: CGWindowID? = nil) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if mode == .frontWindow {
            let available = content.windows.filter { $0.isOnScreen && $0.frame.width > 350 && $0.frame.height > 250 }
            let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.windowID, $0) })
            let position = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
            let ordered = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let underPointer = ordered.compactMap { info -> SCWindow? in
                guard (info[kCGWindowLayer as String] as? Int) == 0,
                      let number = info[kCGWindowNumber as String] as? UInt32,
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(position) else { return nil }
                return byID[number]
            }
            guard let window = preferredWindowID.flatMap({ byID[$0] }) ?? underPointer.first else {
                throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到右键所在窗口"])
            }
            let config = SCStreamConfiguration()
            let scale = screen?.backingScaleFactor ?? 2
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        }
        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可用显示器"])
        }
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
    }
}
