import Foundation

/// 调用 DeepSeek API 对语音转写/手输文本做错别字纠正和润色。
final class TextOptimizer {
    private var key: String?

    func setKey(_ newKey: String?) {
        key = newKey
    }

    var hasKey: Bool {
        !(key?.isEmpty ?? true)
    }

    enum OptimizeError: LocalizedError {
        case noKey
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .noKey: return "未配置 DeepSeek API Key"
            case .badResponse(let message): return message
            }
        }
    }

    /// 把语音转写/手输文本交给 DeepSeek 润色，返回优化后的文本。
    func optimize(_ text: String) async throws -> String {
        guard let key else { throw OptimizeError.noKey }

        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "deepseek-v4-flash",
            "temperature": 0.2,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "system",
                    "content": "你是一个文字润色助手。用户的输入可能来自语音转写，存在错别字、口语化表达或语义不清。请纠正错别字、理顺语句、使表达清晰准确，严格保持原意，不要添加或删除实质内容。只输出润色后的文本本身，不要解释，不要加引号。"
                ],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OptimizeError.badResponse("无效响应")
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw OptimizeError.badResponse("API 返回 \(http.statusCode)：\(String(message.prefix(200)))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OptimizeError.badResponse("响应解析失败")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
