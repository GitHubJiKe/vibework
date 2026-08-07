import Foundation
import AppKit
import ScreenCaptureKit
import VibeCore

/// 推流服务生命周期管理：启动 / 停止 / 切换应用。
/// 引擎回调在各自队列执行，日志与状态变更经回调送回主线程。
final class ServerManager {
    private(set) var server: WebSocketServer?
    private(set) var engine: CaptureEngine?
    private let injector = InputInjector()
    private var activeIndex = 0
    private var activeWindow: SCWindow?
    private var appWindows: [(window: SCWindow, index: Int)] = []
    private var idleTask: Task<Void, Never>?
    private var lastFrameAt = Date.distantPast
    private var maxWidth = 1440

    var onLog: ((String) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?

    var isRunning: Bool { server != nil && engine != nil }
    var currentIndex: Int { activeIndex }
    var appNames: [String] { appWindows.map { $0.window.owningApplication?.applicationName ?? "?" } }
    var currentAppName: String? {
        guard appWindows.indices.contains(activeIndex) else { return nil }
        return appWindows[activeIndex].window.owningApplication?.applicationName
    }

    private func log(_ text: String) {
        onLog?(text)
    }

    /// 启动服务：创建 WebSocket 服务器 + 捕获第一个窗口。
    func start(port: UInt16, fps: Int, quality: Double, maxWidth: Int,
               windows: [SCWindow], token: String?, deepseekKey: String?) async throws {
        await stop()

        guard !windows.isEmpty else {
            throw NSError(domain: "vibeapp", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "请先选择至少一个应用窗口"])
        }
        self.maxWidth = maxWidth
        appWindows = windows.enumerated().map { ($0.element, $0.offset) }
        activeIndex = 0
        activeWindow = appWindows[0].window

        let server = try WebSocketServer(
            port: port,
            viewerHTML: viewerHTML,
            token: token,
            apps: appWindows.map { $0.window.owningApplication?.applicationName ?? "?" }
        )
        server.sourceCount = appWindows.count
        server.setDeepSeekKey(deepseekKey)
        self.server = server
        try await server.start()

        let frameInterval = 1.0 / Double(max(1, fps))
        let engine = CaptureEngine(onFrame: { [weak self] pixelBuffer in
            guard let self, let server = self.server else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastFrameAt) >= frameInterval else { return }
            self.lastFrameAt = now
            guard let jpeg = JPEGEncoder.encode(pixelBuffer, quality: quality) else { return }
            server.broadcast(frame: jpeg)
        })
        self.engine = engine

        let firstWindow = activeWindow!
        do {
            try await engine.start(window: firstWindow, maxWidth: maxWidth)
        } catch {
            await stop()
            throw error
        }

        injector.targetProcessID = firstWindow.owningApplication?.processID

        server.onText { [weak self] json, _ in
            self?.handleText(json)
        }

        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.engine?.nudgeForIdleFrame()
                try? await Task.sleep(for: .milliseconds(200))
                self?.server?.broadcastLastFrameIfIdle()
            }
        }

        log("✓ 服务已启动：端口 \(port)，\(appNames.count) 个应用可切换")
        onRunningChanged?(true)
    }

    /// 停止服务。
    func stop() async {
        idleTask?.cancel()
        idleTask = nil
        await engine?.stop()
        engine = nil
        server?.stop()
        server = nil
        lastFrameAt = .distantPast
        onRunningChanged?(false)
    }

    /// 切换应用（按需停旧流、启新流）。
    func switchApp(to index: Int) async {
        guard let server, let engine, appWindows.indices.contains(index), index != activeIndex else {
            server?.notifySwitch(ok: false, index: index, error: "无效的切换")
            return
        }
        let next = appWindows[index].window
        await engine.stop()
        do {
            try await engine.start(window: next, maxWidth: maxWidth)
            activeIndex = index
            activeWindow = next
            injector.targetProcessID = next.owningApplication?.processID
            injector.resetPointer()
            log("已切换到 \(next.owningApplication?.applicationName ?? "?")")
            server.notifySwitch(ok: true, index: index)
        } catch {
            log("切换失败：\(error.localizedDescription)")
            try? await engine.start(window: activeWindow ?? next, maxWidth: maxWidth)
            server.notifySwitch(ok: false, index: index, error: error.localizedDescription)
        }
    }

    private func handleText(_ json: String) {
        if let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
           obj["type"] as? String == "switch",
           let index = obj["index"] as? Int {
            Task { await switchApp(to: index) }
            return
        }
        guard let data = json.data(using: .utf8),
              let cmd = try? JSONDecoder().decode(RemoteCommand.self, from: data),
              let activeWindow else { return }
        if cmd.type != "mouse" || cmd.action != "move" {
            log("收到控制指令：\(cmd.type)\(cmd.action.map { "/\($0)" } ?? "")")
        }
        injector.targetProcessID = activeWindow.owningApplication?.processID
        injector.handle(cmd, contentFrame: activeWindow.frame)
    }

    /// 局域网 IP（显示访问地址用）。
    static func localIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                                socklen_t(interface.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: host)
                }
            }
            ptr = interface.ifa_next
        }
        freeifaddrs(ifaddr)
        return address
    }
}
