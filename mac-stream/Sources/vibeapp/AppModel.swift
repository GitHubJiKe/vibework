import SwiftUI
import AppKit
import ScreenCaptureKit
import ServiceManagement
import VibeCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum RunStatus: Equatable {
        case idle, starting, running, stopping
    }

    @Published var status: RunStatus = .idle
    @Published var logLines: [String] = []
    @Published var windows: [WindowInfo] = []
    @Published var selected: Set<Int> = []
    @Published var isLoadingWindows = false

    // 设置
    @Published var port = "8090"
    @Published var fps = 15.0
    @Published var quality = 0.65
    @Published var token = ""
    @Published var deepseekKey = KeyStore.load() ?? ""
    @Published var launchAtLogin = false

    private let manager = ServerManager()
    private var windowObjects: [SCWindow] = []

    struct WindowInfo: Identifiable, Hashable {
        let id: Int
        let name: String
        let title: String
        let size: String
    }

    var isRunning: Bool { status == .running }
    var currentAppName: String? { manager.currentAppName }
    var appNames: [String] { manager.appNames }
    var currentIndex: Int { manager.currentIndex }
    var accessibilityGranted: Bool { InputInjector.isTrusted }

    var serverURL: String {
        guard status == .running, let p = UInt16(port) else { return "" }
        let ip = ServerManager.localIP() ?? "Mac 局域网 IP"
        return "http://\(ip):\(p)"
    }

    private init() {
        manager.onLog = { [weak self] text in
            DispatchQueue.main.async { self?.appendLog(text) }
        }
        manager.onRunningChanged = { [weak self] running in
            DispatchQueue.main.async {
                self?.status = running ? .running : .idle
            }
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Task { await refreshWindows() }
    }

    func refreshWindows() async {
        isLoadingWindows = true
        defer { isLoadingWindows = false }
        do {
            let list = try await CaptureEngine.availableWindows(onScreenOnly: false, filterToSupported: true)
            windowObjects = list
            windows = list.enumerated().map { i, w in
                WindowInfo(
                    id: i,
                    name: w.owningApplication?.applicationName ?? "?",
                    title: w.title ?? "",
                    size: "\(Int(w.frame.width))x\(Int(w.frame.height))"
                )
            }
            selected = selected.filter { $0 < windows.count }
            if selected.isEmpty && !windows.isEmpty {
                selected = [0]
            }
        } catch {
            appendLog("获取窗口列表失败：\(error.localizedDescription)")
            appendLog("若提示屏幕录制权限：请到 系统设置 → 隐私与安全性 → 屏幕录制 勾选 VibePilot，然后完全退出并重新打开本 App")
        }
    }

    func start() async {
        guard status == .idle else { return }
        status = .starting
        defer { if status == .starting { status = .idle } }

        let portNum = UInt16(port) ?? 8090
        let chosen = selected.sorted().compactMap { i in
            windowObjects.indices.contains(i) ? windowObjects[i] : nil
        }
        guard !chosen.isEmpty else {
            appendLog("请先选择至少一个应用窗口")
            return
        }
        if !InputInjector.isTrusted {
            appendLog("⚠️ 辅助功能未授权：画面可推流但无法控制（发消息/点击/滚动）。")
            appendLog("   请到 系统设置 → 隐私与安全性 → 辅助功能 勾选 VibePilot，然后完全退出并重新打开本 App")
        }
        KeyStore.save(deepseekKey.trimmingCharacters(in: .whitespaces).isEmpty ? nil : deepseekKey.trimmingCharacters(in: .whitespaces))
        do {
            try await manager.start(
                port: portNum,
                fps: Int(fps),
                quality: quality,
                maxWidth: 1440,
                windows: chosen,
                token: token.isEmpty ? nil : token,
                deepseekKey: deepseekKey.trimmingCharacters(in: .whitespaces).isEmpty ? nil : deepseekKey.trimmingCharacters(in: .whitespaces)
            )
            status = .running
        } catch {
            appendLog("启动失败：\(error.localizedDescription)")
        }
    }

    func stop() async {
        guard status == .running || status == .starting else { return }
        status = .stopping
        await manager.stop()
        status = .idle
    }

    func switchApp(to index: Int) async {
        guard isRunning else { return }
        await manager.switchApp(to: index)
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLogin = false
            } else {
                try SMAppService.mainApp.register()
                launchAtLogin = true
            }
        } catch {
            appendLog("开机自启设置失败：\(error.localizedDescription)")
        }
    }

    func appendLog(_ text: String) {
        logLines.append(text)
        if logLines.count > 300 {
            logLines.removeFirst(logLines.count - 300)
        }
    }
}
