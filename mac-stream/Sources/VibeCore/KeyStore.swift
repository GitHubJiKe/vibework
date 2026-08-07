import Foundation

/// 把 DeepSeek Key 持久化到 ~/.vibework/deepseek.key，
/// 避免重启程序后丢失（之前仅存内存，重启要重新设置）。
public enum KeyStore {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vibework", isDirectory: true)
            .appendingPathComponent("deepseek.key")
    }

    public static func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    public static func save(_ key: String?) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let key, !key.isEmpty {
                try key.data(using: .utf8)?.write(to: fileURL, options: .atomic)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            } else {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("保存 DeepSeek Key 失败：\(error.localizedDescription)")
        }
    }
}
