import SwiftUI
import ServiceManagement
import VibeCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showQR = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            HStack(alignment: .top, spacing: 16) {
                windowList
                    .frame(minWidth: 280, idealWidth: 320)
                settingsPanel
                    .frame(minWidth: 300, idealWidth: 340)
            }
            .padding(12)
            Divider()
            logPanel
        }
        .frame(minWidth: 660, minHeight: 560)
        .onAppear { checkPermissions() }
        .sheet(isPresented: $showQR) {
            QRCodeView(url: model.serverURL)
        }
    }

    // MARK: - 状态栏
    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.isRunning ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(model.isRunning ? "正在推流" : "未运行")
                .font(.headline)
            if model.isRunning {
                Text(model.currentAppName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.serverURL)
                    .font(.system(.body, design: .monospaced))
                Button("二维码") { showQR = true }
                Button("复制地址") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.serverURL, forType: .string)
                }
            } else {
                Spacer()
                Button("刷新窗口") { Task { await model.refreshWindows() } }
            }
        }
        .padding(10)
        .background(.bar)
    }

    // MARK: - 窗口列表
    private var windowList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("选择要控制的应用")
                    .font(.headline)
                Spacer()
                if model.isLoadingWindows {
                    ProgressView().controlSize(.small)
                }
                Button("刷新") { Task { await model.refreshWindows() } }
                    .controlSize(.small)
            }
            if model.windows.isEmpty {
                VStack(spacing: 8) {
                    Text("没有找到可捕获的窗口")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("常见原因：未授予屏幕录制权限，或应用窗口被最小化。\n授权后请完全退出并重新打开 VibePilot。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("打开屏幕录制设置") { openScreenRecordingSettings() }
                        .controlSize(.small)
                    Button("重新刷新") { Task { await model.refreshWindows() } }
                        .controlSize(.small)
                }
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.windows) { w in
                            WindowRow(window: w, isSelected: model.selected.contains(w.id)) {
                                toggleSelect(w.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func toggleSelect(_ id: Int) {
        if model.selected.contains(id) {
            model.selected.remove(id)
        } else {
            model.selected.insert(id)
        }
    }

    // MARK: - 设置面板
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置")
                .font(.headline)
            Form {
                TextField("端口", text: $model.port)
                HStack {
                    Text("帧率")
                    Slider(value: $model.fps, in: 5...30, step: 1)
                    Text("\(Int(model.fps))")
                        .monospacedDigit()
                        .frame(width: 28)
                }
                HStack {
                    Text("质量")
                    Slider(value: $model.quality, in: 0.2...1.0, step: 0.05)
                    Text(String(format: "%.2f", model.quality))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                TextField("访问口令（可选）", text: $model.token)
                TextField("DeepSeek Key（可选）", text: $model.deepseekKey)
                Toggle("开机自启", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { newValue in
                        if newValue != (SMAppService.mainApp.status == .enabled) {
                            model.toggleLaunchAtLogin()
                        }
                    }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                if model.isRunning {
                    Button("停止", role: .destructive) {
                        Task { await model.stop() }
                    }
                } else {
                    Button("开始推流") {
                        Task { await model.start() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                if !InputInjector.isTrusted {
                    Button("授权辅助功能") { openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - 日志
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("日志")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") { model.logLines.removeAll() }
                    .controlSize(.mini)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logEnd")
                }
                .frame(maxHeight: 130)
                .onChange(of: model.logLines.count) { _ in
                    withAnimation(.none) { proxy.scrollTo("logEnd", anchor: .bottom) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - 权限
    private func checkPermissions() {
        if InputInjector.isTrusted {
            model.appendLog("✓ 辅助功能权限正常")
        } else {
            model.appendLog("⚠️ 辅助功能权限未授予：控制功能不可用，点击「授权辅助功能」")
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

private struct WindowRow: View {
    let window: AppModel.WindowInfo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.name)
                        .font(.body)
                    if !window.title.isEmpty {
                        Text(window.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(window.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
