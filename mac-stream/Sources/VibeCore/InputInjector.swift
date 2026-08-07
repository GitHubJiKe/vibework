import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

/// 客户端（手机浏览器）发来的控制指令。
public struct RemoteCommand: Decodable {
    public let type: String          // mouse / scroll / key / text；scroll: dx>0 右移 / dy>0 下移（单位：档）
    public let action: String?       // mouse: move/down/up/click/doubleclick/rightclick
    public let x: Double?            // 归一化坐标 0-1（左上原点）
    public let y: Double?
    public let dx: Double?
    public let dy: Double?
    public let key: String?
    public let flags: [String]?      // cmd/shift/alt/ctrl
    public let text: String?
    public let edge: String?         // scroll: top/bottom 滚到顶部/底部
    public let enter: Bool?          // text: 输入完成后自动补一次回车（发送）
}

/// 用 CGEvent 把手机端的控制指令注入到 Mac 的鼠标/键盘。
/// 需要「辅助功能（Accessibility）」权限。
public final class InputInjector {

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public init() {}

    /// 被控窗口所属 App 的进程号；注入前自动把它激活到最前，
    /// 避免文字/按键落入其他 App（比如正在操作的 Codex）。
    public var targetProcessID: pid_t?

    /// 最近一次鼠标/触控落点（全局坐标）。滚动优先发生在该位置，
    /// 保证滚动作用于用户正在看的区域；从未操作过则回退到窗口中心。
    private var lastPointer: CGPoint?
    /// 上一次滚动的锚点；鼠标位置没变时连续滚动不再重复定位（更跟手）。
    private var lastScrollAnchor: CGPoint?

    /// 切换被控应用后调用：清掉旧窗口的鼠标位置记忆，滚动回退到新窗口中心。
    public func resetPointer() {
        lastPointer = nil
        lastScrollAnchor = nil
    }

    /// 当前被控应用的 bundle id（诊断 + Codex 专用聚焦用）。
    private var currentBundle: String? {
        guard let pid = targetProcessID else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private let keyCodes: [String: CGKeyCode] = [
        "enter": 36, "return": 36, "tab": 48, "esc": 53, "escape": 53,
        "backspace": 51, "delete": 51, "forwarddelete": 117, "forward_delete": 117,
        "space": 49, "up": 126, "down": 125, "left": 123, "right": 124,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
        "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
        "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25,
        "`": 50, "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
        ";": 41, "'": 39, ",": 43, ".": 47, "/": 44
    ]

    public func handle(_ cmd: RemoteCommand, contentFrame: CGRect) {
        switch cmd.type {
        case "mouse":
            guard let x = cmd.x, let y = cmd.y else { return }
            let point = mapPoint(x: x, y: y, frame: contentFrame)
            switch cmd.action {
            case "move": move(to: point)
            case "down":
                activateTarget()
                mouseDown(at: point)
            case "up": mouseUp(at: point)
            case "click":
                activateTarget()
                click(at: point)
            case "doubleclick":
                activateTarget()
                doubleClick(at: point)
            case "rightclick":
                activateTarget()
                rightClick(at: point)
            default: break
            }
        case "scroll":
            if let edge = cmd.edge {
                activateTarget()
                scrollToEdge(edge: edge, frame: contentFrame)
            } else {
                let dx = cmd.dx ?? 0
                let dy = cmd.dy ?? 0
                if dx != 0 || dy != 0 {
                    activateTarget()
                    scroll(dx: dx, dy: dy, frame: contentFrame)
                }
            }
        case "key":
            if let key = cmd.key {
                let flags = cmd.flags ?? []
                activateTarget()
                // 等激活生效后再按键，避免事件落到切换前的旧窗口
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.keyEvent(key: key, flags: flags)
                }
            }
        case "text":
            if let text = cmd.text {
                activateTarget()
                let frame = contentFrame
                let bundle = currentBundle
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    // 仅 Codex：先点击底部输入框拿到焦点（Cursor 激活后焦点天然在输入框，不点）
                    if bundle == "com.openai.codex" {
                        let p = self.mapPoint(x: 0.5, y: 0.88, frame: frame)
                        self.click(at: p)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + (bundle == "com.openai.codex" ? 0.4 : 0.0)) {
                        self.typeText(text)
                        if cmd.enter == true {
                            // 等文本全部注入完，再补一次回车触发对话发送
                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                                self.keyEvent(key: "enter", flags: [])
                            }
                        }
                    }
                }
            }
        default:
            break
        }
    }

    /// 把被控窗口的 App 激活到最前。
    private func activateTarget() {
        guard let pid = targetProcessID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    /// 把客户端归一化坐标（0-1，左上原点）映射到 Mac 全局坐标。
    /// ScreenCaptureKit 的 frame 与 CGEvent 鼠标坐标同为「全局显示坐标（左上原点）」，无需翻转 Y。
    private func mapPoint(x: Double, y: Double, frame: CGRect) -> CGPoint {
        let nx = max(0, min(1, x))
        let ny = max(0, min(1, y))
        return CGPoint(
            x: frame.origin.x + nx * frame.width,
            y: frame.origin.y + ny * frame.height
        )
    }

    // MARK: - 鼠标

    func move(to point: CGPoint) {
        lastPointer = point
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func mouseDown(at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func mouseUp(at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func click(at point: CGPoint) {
        mouseDown(at: point)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.mouseUp(at: point)
        }
    }

    func doubleClick(at point: CGPoint) {
        mouseDown(at: point); mouseUp(at: point)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.mouseDown(at: point)
            self.mouseUp(at: point)
        }
    }

    func rightClick(at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)?
            .post(tap: .cghidEventTap)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { [weak self] in
            CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)?
                .post(tap: .cghidEventTap)
            _ = self
        }
    }

    func scroll(dx: Double, dy: Double, frame: CGRect) {
        // 固定锚定到窗口中央的聊天/主内容区：
        // 若跟随用户点过的地方，可能落在侧栏/空白区，滚轮事件无效。
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let anchorChanged = lastScrollAnchor != point
        if anchorChanged {
            move(to: point)
            lastScrollAnchor = point
        }
        let postWheel = {
            // wheel1 正=向上滚动；客户端 dy>0 表示向下滚动，所以取反。
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: Int32(-dy * 40), wheel2: Int32(-dx * 40), wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
        if anchorChanged {
            // 鼠标刚移动，等它落位再滚：滚轮只发给「鼠标悬停位置」的窗口。
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.04) { postWheel() }
        } else {
            postWheel()
        }
    }

    /// 滚到顶部/底部：发几发超大滚轮量，应用会直接钳制到滚动边界。
    func scrollToEdge(edge: String, frame: CGRect) {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        move(to: point)
        let delta: Int32 = edge == "top" ? 200_000 : -200_000
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.04) {
            for _ in 0..<4 {
                CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                        wheel1: delta, wheel2: 0, wheel3: 0)?
                    .post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
    }

    // MARK: - 键盘

    func keyEvent(key: String, flags: [String]) {
        let lower = key.lowercased()
        guard let code = keyCodes[lower] else {
            print("未知按键：\(key)")
            return
        }
        var flag: CGEventFlags = []
        for f in flags {
            switch f.lowercased() {
            case "cmd", "command": flag.insert(.maskCommand)
            case "shift": flag.insert(.maskShift)
            case "alt", "option": flag.insert(.maskAlternate)
            case "ctrl", "control": flag.insert(.maskControl)
            default: break
            }
        }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        down?.flags = flag
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        up?.flags = flag
        up?.post(tap: .cghidEventTap)
    }

    /// 把任意文字（含中文）逐字注入到当前焦点输入框。
    func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.utf16 {
            var ch = scalar
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            up?.post(tap: .cghidEventTap)
        }
    }
}
