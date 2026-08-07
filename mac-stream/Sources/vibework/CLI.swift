import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics
import ApplicationServices

@main
struct VibeworkMain {

    static func main() async throws {
        // 命令行进程需要先初始化 AppKit/WindowServer 连接，
        // 否则使用 ScreenCaptureKit 枚举窗口时会触发 CGS_REQUIRE_INIT 崩溃。
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        // 显示器熄屏时 ScreenCaptureKit 一帧都产不出来，先主动检测。
        let displayID = CGMainDisplayID()
        if CGDisplayIsAsleep(displayID) != 0 {
            print("⚠️ 检测到显示器处于熄屏/睡眠状态——此时捕获不到任何画面。")
            print("  请先执行 caffeinate -d 保持屏幕常亮，并保持 Mac 未锁屏。")
        }

        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") {
            print(usage)
            return
        }
        if args.contains("--list") {
            await listWindows()
            return
        }
        if args.contains("--probe") {
            let idx = value(for: "--probe", in: args).flatMap(Int.init) ?? 0
            await runProbe(windowIndex: idx)
            return
        }
        let port = value(for: "--port", in: args).flatMap(UInt16.init) ?? 8080
        let fps = min(30, max(1, value(for: "--fps", in: args).flatMap(Int.init) ?? 15))
        let quality = min(1.0, max(0.1, value(for: "--quality", in: args).flatMap(Double.init) ?? 0.65))
        let maxWidth = min(2560, max(320, value(for: "--max-width", in: args).flatMap(Int.init) ?? 1440))
        let windowIndex = value(for: "--window", in: args).flatMap(Int.init)
        let token = value(for: "--token", in: args)
        // 命令行优先；没传则读取本地保存的 Key，避免重启后丢失
        let deepseekKey = value(for: "--deepseek-key", in: args) ?? KeyStore.load()
        if let deepseekKey {
            KeyStore.save(deepseekKey)
        }

        if args.contains("--snapshot") {
            let flagIndex = args.firstIndex(of: "--snapshot")!
            var snapshotPath = "/tmp/vibework-snapshot.jpg"
            if args.indices.contains(flagIndex + 1), !args[flagIndex + 1].hasPrefix("-") {
                snapshotPath = args[flagIndex + 1]
            }
            await takeSnapshot(path: snapshotPath, maxWidth: maxWidth)
            return
        }

        let server = try WebSocketServer(port: port, viewerHTML: viewerHTML, token: token)
        server.setDeepSeekKey(deepseekKey)
        if token != nil {
            print("🔒 访问口令已启用：手机打开页面后需输入口令才能连接")
        }
        do {
            try await server.start()
        } catch {
            print("服务器启动失败：\(error.localizedDescription)")
            print("很可能是端口 \(port) 被占用。换一个端口重试，例如：--port 8090")
            print("如果想查谁占用了端口：lsof -nP -iTCP:\(port) -sTCP:LISTEN")
            return
        }

        if args.contains("--demo") {
            print("演示模式：不捕获屏幕，推模拟画面。")
            var frame = 0
            let interval = 1.0 / Double(fps)
            while true {
                let image = Demo.makeImage(frame: frame)
                if let data = JPEGEncoder.encode(image, quality: quality) {
                    server.broadcast(frame: data)
                }
                frame += 1
                try await Task.sleep(for: .seconds(interval))
            }
        }

        if !args.contains("--no-capture") {
            let windows: [SCWindow]
            do {
                windows = try await CaptureEngine.availableWindows()
            } catch {
                print("无法访问屏幕内容：\(error.localizedDescription)")
                print("请在 系统设置 → 隐私与安全性 → 屏幕录制 中授权，然后重试。")
                return
            }
            guard !windows.isEmpty else {
                print("没有可捕获的窗口。请先打开目标应用再试。")
                return
            }
            let frameInterval = 1.0 / Double(fps)
            var capturedCount = 0
            var encodedCount = 0
            var encodeErrorPrinted = false
            let engine = CaptureEngine(onFrame: { pixelBuffer in
                capturedCount += 1
                guard Date().timeIntervalSince(lastFrameAt) >= frameInterval else { return }
                lastFrameAt = Date()
                guard let jpeg = JPEGEncoder.encode(pixelBuffer, quality: quality) else {
                    if !encodeErrorPrinted {
                        encodeErrorPrinted = true
                        print("⚠️ 帧编码失败（VideoToolbox 与 CoreImage 均失败），请把此信息反馈")
                    }
                    return
                }
                encodedCount += 1
                server.broadcast(frame: jpeg)
            })

            let injector = InputInjector()
            if InputInjector.isTrusted {
                print("✓ 控制功能已启用（辅助功能权限正常）——手机端可触控/按键/语音控制 Mac")
            } else {
                print("⚠️ 「辅助功能」权限未授予：控制功能暂不可用（画面预览不受影响）")
                print("  请到 系统设置 → 隐私与安全性 → 辅助功能 勾选运行本程序的终端，然后重启本程序。")
            }

            if args.contains("--screen") {
                // 整屏捕获：单源，控制指令作用于整屏
                var contentFrame = CGRect.zero
                do {
                    let displays = try await CaptureEngine.availableDisplays()
                    guard let display = displays.first else {
                        print("没有可捕获的显示器")
                        return
                    }
                    contentFrame = display.frame
                    try await engine.start(display: display, maxWidth: maxWidth)
                } catch {
                    print("启动捕获失败：\(error.localizedDescription)")
                    print("若提示权限不足，请在 系统设置 → 隐私与安全性 → 屏幕录制 中授权后重试。")
                    return
                }
                server.onText { json, _ in
                    guard let data = json.data(using: .utf8),
                          let cmd = try? JSONDecoder().decode(RemoteCommand.self, from: data) else { return }
                    if cmd.type != "mouse" || cmd.action != "move" {
                        print("收到控制指令：\(cmd.type)\(cmd.action.map { "/\($0)" } ?? "")")
                    }
                    injector.handle(cmd, contentFrame: contentFrame)
                }
            } else {
                // 窗口捕获：单/多应用（按需切换，同一时刻只捕获一个窗口）
                var appWindows: [(window: SCWindow, index: Int)] = []
                if let appsArg = value(for: "--apps", in: args) {
                    let indices = appsArg.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    for idx in indices {
                        guard windows.indices.contains(idx) else {
                            print("窗口索引 \(idx) 无效。先运行 --list 查看可用窗口。")
                            return
                        }
                        if !appWindows.contains(where: { $0.index == idx }) {
                            appWindows.append((windows[idx], idx))
                        }
                    }
                } else if let windowIndex {
                    guard windows.indices.contains(windowIndex) else {
                        print("窗口索引无效。先运行 --list 查看可用窗口。")
                        return
                    }
                    appWindows = [(windows[windowIndex], windowIndex)]
                } else {
                    if let picked = pickWindow(from: windows) {
                        let idx = windows.firstIndex(where: { $0.windowID == picked.windowID }) ?? 0
                        appWindows = [(picked, idx)]
                        print("自动选中：\(describe(picked))")
                    } else {
                        appWindows = [(windows[0], 0)]
                        print("未匹配到常用编程窗口，使用：\(describe(windows[0]))")
                    }
                }
                guard !appWindows.isEmpty else { return }

                var activeIndex = 0
                var activeWindow = appWindows[0].window
                do {
                    try await engine.start(window: activeWindow, maxWidth: maxWidth)
                } catch {
                    print("启动捕获失败：\(error.localizedDescription)")
                    print("若提示权限不足，请在 系统设置 → 隐私与安全性 → 屏幕录制 中授权后重试。")
                    return
                }
                injector.targetProcessID = activeWindow.owningApplication?.processID
                server.sourceCount = appWindows.count
                server.apps = appWindows.map { $0.window.owningApplication?.applicationName ?? "?" }
                if appWindows.count > 1 {
                    print("已加载 \(appWindows.count) 个应用（网页端顶部可切换）：")
                    for (i, w) in appWindows.enumerated() {
                        print("  [\(i)] \(w.window.owningApplication?.applicationName ?? "?")")
                    }
                }

                // 手机端控制指令入口：切换应用（按需停旧流启新流）或注入鼠标/键盘。
                server.onText { json, _ in
                    if let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                       obj["type"] as? String == "switch",
                       let index = obj["index"] as? Int,
                       appWindows.indices.contains(index),
                       index != activeIndex {
                        let nextWindow = appWindows[index].window
                        Task {
                            await engine.stop()
                            do {
                                try await engine.start(window: nextWindow, maxWidth: maxWidth)
                                activeIndex = index
                                activeWindow = nextWindow
                                injector.targetProcessID = nextWindow.owningApplication?.processID
                                injector.resetPointer()
                                print("已切换到 \(nextWindow.owningApplication?.applicationName ?? "?")")
                                server.notifySwitch(ok: true, index: index)
                            } catch {
                                print("切换失败：\(error.localizedDescription)")
                                try? await engine.start(window: activeWindow, maxWidth: maxWidth)
                                server.notifySwitch(ok: false, index: index, error: error.localizedDescription)
                            }
                        }
                        return
                    }
                    guard let data = json.data(using: .utf8),
                          let cmd = try? JSONDecoder().decode(RemoteCommand.self, from: data) else { return }
                    if cmd.type != "mouse" || cmd.action != "move" {
                        print("收到控制指令：\(cmd.type)\(cmd.action.map { "/\($0)" } ?? "")")
                    }
                    injector.targetProcessID = activeWindow.owningApplication?.processID
                    injector.handle(cmd, contentFrame: activeWindow.frame)
                }
            }

            // 启动 8 秒后诊断一次推流是否真的有帧，方便定位问题。
            Task {
                try? await Task.sleep(for: .seconds(8))
                if encodedCount > 0 {
                    print("✓ 画面帧推流正常（8 秒内发出 \(encodedCount) 帧）")
                } else if capturedCount > 0 {
                    print("✓ 捕获正常（8 秒内捕获原始帧 \(capturedCount) 个），但画面基本静止没有新帧。")
                    print("  已启用「静止时每秒重发最后一帧」，客户端应能看到当前屏幕。")
                } else {
                    print("⚠️ 启动 8 秒后仍未推流出画面帧（捕获原始帧 \(capturedCount) 个）")
                    if capturedCount == 0 {
                        print("  请确认：目标窗口可见且未最小化；屏幕录制权限已授予，且授权后重新打开过终端。")
                        print("  诊断建议：① 检查终端是否显示过「显示器处于熄屏」警告；② 用 --snapshot 做一次性截图诊断；③ 用 --screen 模式对照。")
                    } else {
                        print("  原始帧已捕获但编码失败，请把上方诊断信息反馈给我。")
                    }
                }
            }

            // 屏幕画面静止时 ScreenCaptureKit 不产新帧，这里每秒重发最后一帧，
            // 并先通过 nudge 强制系统出一帧，保证手机/浏览器始终能看到当前屏幕。
            Task {
                while true {
                    try? await Task.sleep(for: .seconds(1))
                    engine.nudgeForIdleFrame()
                    try? await Task.sleep(for: .milliseconds(200))
                    server.broadcastLastFrameIfIdle()
                }
            }
        } else {
            print("仅 HTTP/WS 服务模式（--no-capture），不捕获屏幕。")
        }
        print("----------------------------------------")

        while true {
            try await Task.sleep(for: .seconds(1))
        }
    }

    private static var lastFrameAt = Date.distantPast

    private static func describe(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? "?"
        let bundle = window.owningApplication?.bundleIdentifier ?? ""
        let title = window.title ?? ""
        return "\(app)（\(bundle)）— \(title)（\(Int(window.frame.width))x\(Int(window.frame.height))pt）"
    }

    private static let preferredAppNames = [
        "Cursor", "Visual Studio Code", "Code", "Warp", "iTerm2",
        "Terminal", "Ghostty", "ChatGPT", "Google Chrome", "Safari", "Xcode"
    ]

    private static func pickWindow(from windows: [SCWindow]) -> SCWindow? {
        for name in preferredAppNames {
            if let match = windows.first(where: { $0.owningApplication?.applicationName == name }) {
                return match
            }
        }
        return nil
    }

    private static func listWindows() async {
        do {
            let windows = try await CaptureEngine.availableWindows()
            for (index, window) in windows.enumerated() {
                print("[\(index)] \(describe(window))")
            }
            print("共 \(windows.count) 个窗口。使用 --window <序号> 指定目标。")
        } catch {
            print("获取窗口列表失败：\(error.localizedDescription)")
            print("提示：首次使用请到 系统设置 → 隐私与安全性 → 屏幕录制 授权运行它的终端（或打包成 .app 后授权该 App）。")
        }
    }

    private static func takeSnapshot(path: String, maxWidth: Int) async {
        do {
            let displays = try await CaptureEngine.availableDisplays()
            guard let display = displays.first else {
                print("没有可捕获的显示器")
                return
            }
            print("正在对整屏做一次性截图诊断（\(Int(display.width))x\(Int(display.height))pt）...")
            guard let image = try await CaptureEngine.snapshot(display: display, maxWidth: maxWidth) else {
                print("截图失败：没有返回图像")
                return
            }
            guard let jpeg = JPEGEncoder.encode(image, quality: 0.8) else {
                print("截图成功但 JPEG 编码失败")
                return
            }
            try jpeg.write(to: URL(fileURLWithPath: path))
            print("✅ 截图已保存：\(path)（\(image.width)x\(image.height)px）")
            print("  打开这张图：如果是正常桌面画面 → 权限和捕获管线都正常，问题在流本身；")
            print("  如果是全黑 → 显示器熄屏/锁屏，先 caffeinate -d。")
        } catch {
            print("❌ 截图失败：\(error.localizedDescription)")
            print("  请确认「屏幕录制」权限授予了运行本程序的终端，而不是被录制的 App。")
        }
    }

    /// 事件注入诊断：验证窗口坐标、鼠标移动、滚轮是否真正到达目标窗口。
    /// 用法: vibework --probe <窗口序号>
    private static func runProbe(windowIndex: Int) async {
        do {
            let windows = try await CaptureEngine.availableWindows()
            guard windows.indices.contains(windowIndex) else {
                print("窗口序号 \(windowIndex) 无效。先运行 --list 查看可用窗口。")
                return
            }
            let w = windows[windowIndex]
            let app = w.owningApplication
            print("=== 事件注入诊断 ===")
            print("窗口：\(describe(w))")
            print("SCK frame: \(w.frame)  （左上原点，points）")
            print("pid: \(app?.processID ?? -1)  bundle: \(app?.bundleIdentifier ?? "?")")
            print("当前前端应用: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

            // 通过辅助功能 API 读取窗口位置，与 SCK frame 对比坐标系
            if let pid = app?.processID {
                let axApp = AXUIElementCreateApplication(pid)
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement],
                   let first = axWindows.first {
                    var posRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(first, kAXPositionAttribute as CFString, &posRef) == .success,
                       AXUIElementCopyAttributeValue(first, kAXSizeAttribute as CFString, &sizeRef) == .success,
                       let pos = posRef, let size = sizeRef {
                        var p = CGPoint.zero
                        var s = CGSize.zero
                        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
                        AXValueGetValue(size as! AXValue, .cgSize, &s)
                        print("AX 窗口位置: \(p) 尺寸: \(s)  （对比 SCK frame 是否一致）")
                    }
                }
            }

            // 激活目标窗口（SCK 的 app 对象无 activate，用 NSRunningApplication）
            let nsApp = app.map { NSRunningApplication(processIdentifier: $0.processID) } ?? nil
            nsApp?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            try? await Task.sleep(for: .milliseconds(500))
            print("激活后前端应用: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

            // 移动鼠标到窗口中心，再读回实际位置
            let center = CGPoint(x: w.frame.midX, y: w.frame.midY)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(300))
            let current = CGEvent(source: nil)?.location ?? .zero
            print("目标鼠标位置: \(center)")
            print("实际鼠标位置: \(current)   （应等于目标，否则坐标系不一致）")

            // 发一次明显的大滚轮事件，观察目标窗口是否滚动
            print("发送大滚轮事件（wheel1=-600px），请观察 Codex/Cursor 是否滚动...")
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: -600, wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
            try? await Task.sleep(for: .seconds(1))

            // 模拟点击窗口底部中央（输入框位置），观察是否聚焦
            let input = CGPoint(x: w.frame.midX, y: w.frame.origin.y + w.frame.height * 0.88)
            print("模拟点击输入框位置: \(input)，请观察该窗口输入框是否获得焦点...")
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: input, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(80))
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: input, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(500))
            print("=== 诊断完成 ===")
            print("判断依据：")
            print("1. SCK frame 与 AX 位置若差 2 倍 → 坐标系单位不一致（points vs 像素）")
            print("2. 实际鼠标位置 ≠ 目标 → 鼠标移动未生效")
            print("3. 滚轮后目标窗口滚动 → 注入有效；没滚动 → 事件没到达或该位置不可滚动")
            print("4. 点击后输入框有光标 → 点击有效；否则事件未到达")
        } catch {
            print("诊断失败：\(error.localizedDescription)")
        }
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static let usage = """
    vibework · mac-stream

    用法：
      vibework --list                  列出可捕获的窗口
      vibework [选项]                  启动推流

    选项：
      --window <序号>   捕获指定窗口（配合 --list 查看序号）
      --apps <序号,序号,...>  同时加载多个窗口，网页端顶部可切换（如 --apps 2,3,4）
      --port <端口>     监听端口，默认 8080
      --fps <1-30>      帧率，默认 15
      --quality <0-1>   JPEG 质量，默认 0.65
      --max-width <宽>  输出最大宽度（像素），默认 1440
      --demo            推模拟画面，不捕获屏幕
      --no-capture      只启动 HTTP/WS 服务，不捕获
      --screen          捕获整个主屏幕（窗口捕获不出帧时用于诊断/兜底）
      --snapshot [路径]  一次性整屏截图诊断，默认 /tmp/vibework-snapshot.jpg
      --probe <序号>    事件注入诊断：验证坐标/鼠标/滚轮/点击是否到达目标窗口
      --token <口令>     访问口令：手机打开页面需输入口令才能连接
      --deepseek-key <key>   DeepSeek API Key：AI 润色输入文本（页面 ⚙ 也可设置）

    示例：
      vibework --list
      vibework --window 2 --port 9090 --fps 20
      vibework --apps 2,3,4 --port 9090 --fps 15
      vibework --screen --port 8090
      vibework --snapshot
      vibework --window 2 --port 8090 --token mypass --deepseek-key sk-xxxx
    """
}
