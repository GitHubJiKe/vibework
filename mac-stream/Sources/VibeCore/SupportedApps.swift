import Foundation
import ScreenCaptureKit

/// 受支持的 AI 编程 / 终端类应用白名单。
/// 按 bundle id 与应用名双匹配（bundle id 更精确，应用名兜底兼容不同版本）。
public enum SupportedApps {
    public static let names: Set<String> = [
        "Codex",
        "ChatGPT",
        "Cursor",
        "Visual Studio Code",
        "Code",
        "iTerm2",
        "Terminal",
    ]

    public static let bundleIDs: Set<String> = [
        "com.openai.codex",              // Codex / ChatGPT 桌面
        "com.openai.chat",               // ChatGPT
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.microsoft.VSCode",          // VS Code
        "com.googlecode.iterm2",         // iTerm2
        "com.apple.Terminal",            // 终端
    ]

    public static func isSupported(_ app: SCRunningApplication?) -> Bool {
        guard let app else { return false }
        if bundleIDs.contains(app.bundleIdentifier) {
            return true
        }
        return names.contains(app.applicationName)
    }
}
