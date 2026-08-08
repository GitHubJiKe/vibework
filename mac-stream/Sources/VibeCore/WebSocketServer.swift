import Foundation
import Network
import CryptoKit

/// 基于 Network 框架的极简 WebSocket 服务器：
/// - GET /           返回内嵌查看页
/// - GET /stream     WebSocket 升级，后续接收二进制帧（JPEG）
public final class WebSocketServer {
    private struct Client {
        let conn: NWConnection
        var sending = false
        var nextFrame: Data?
        var source = 0   // 当前订阅的捕获源（多应用切换用）
    }

    private let listener: NWListener
    private let viewerHTML: String
    public var apps: [String] = []
    private var clients: [ObjectIdentifier: Client] = [:]
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private var onTextMessage: ((String, Int) -> Void)?
    private let textOptimizer = TextOptimizer()
    private let token: String?
    private let queue = DispatchQueue(label: "vibepilot.ws", qos: .userInitiated)
    private var lastFrames: [Int: Data] = [:]
    private var lastSendAt: [Int: Date] = [:]
    private let idleResendInterval: TimeInterval = 1.0
    /// 捕获源数量（多应用窗口数）。网页端切换应用时 index 必须小于该值。
    public var sourceCount = 1

    public init(port: UInt16, viewerHTML: String, token: String?, apps: [String] = []) throws {
        self.viewerHTML = viewerHTML
        if !apps.isEmpty { self.apps = apps }
        self.token = token
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
    }

    /// 启动监听；端口被占用等错误会以 throw 形式返回，便于命令行优雅退出。
    public func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleNewConnection(conn)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = self?.listener.port.map(String.init(describing:)) ?? "?"
                    print("流服务器已就绪，端口 \(port)")
                    if !didResume { didResume = true; continuation.resume() }
                case .failed(let error):
                    if !didResume { didResume = true; continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// 停止监听并断开所有客户端（App 停止/重启服务用）。
    public func stop() {
        queue.sync {
            listener.cancel()
            for (_, client) in clients {
                client.conn.cancel()
            }
            clients.removeAll()
            receiveBuffers.removeAll()
            lastFrames.removeAll()
            lastSendAt.removeAll()
        }
    }

    /// 推一帧给订阅了该捕获源的客户端（始终发送最新帧，繁忙时丢弃中间帧）。
    public func broadcast(frame: Data, source: Int = 0) {
        let encoded = encodeFrame(frame)
        queue.async { [weak self] in
            guard let self else { return }
            self.lastFrames[source] = encoded
            self.lastSendAt[source] = Date()
            self.sendToSource(encoded, source: source)
        }
    }

    /// 屏幕画面静止时定期重发各源最后一帧，保证客户端始终能看到当前屏幕。
    /// 如果帧正在正常流动则跳过，避免重复发送。
    public func broadcastLastFrameIfIdle() {
        queue.async { [weak self] in
            guard let self else { return }
            for (source, frame) in self.lastFrames {
                let last = self.lastSendAt[source] ?? .distantPast
                if Date().timeIntervalSince(last) >= self.idleResendInterval {
                    self.lastSendAt[source] = Date()
                    self.sendToSource(frame, source: source)
                }
            }
        }
    }

    /// 注册客户端文本消息（控制指令）回调。
    public func onText(_ handler: @escaping (String, Int) -> Void) {
        onTextMessage = handler
    }

    /// 设置 DeepSeek API Key（启动参数或页面 ⚙ 设置）。
    public func setDeepSeekKey(_ key: String?) {
        textOptimizer.setKey(key)
    }

    /// 多应用切换结果（切流完成后由 CLI 调用，广播给所有客户端）。
    public func notifySwitch(ok: Bool, index: Int, error: String? = nil) {
        let err = error.map { ", \"error\":\(Self.jsonString($0))" } ?? ""
        let frame = "{\"type\":\"switch_ok\",\"ok\":\(ok),\"index\":\(index)\(err)}"
        queue.async { [weak self] in
            guard let self else { return }
            for (_, client) in self.clients {
                self.sendTextFrame(frame, to: client.conn)
            }
        }
    }

    private func sendToSource(_ encoded: Data, source: Int) {
        let ids = Array(self.clients.keys)
        for id in ids {
            guard var client = self.clients[id] else { continue }
            if client.source != source { continue }
            if client.sending {
                client.nextFrame = encoded
                self.clients[id] = client
                continue
            }
            client.sending = true
            self.clients[id] = client
            self.sendFrame(encoded, for: id)
        }
    }

    // MARK: - 连接处理

    private func handleNewConnection(_ conn: NWConnection) {
        print("WS: 新连接 \(conn.endpoint)")
        conn.start(queue: queue)
        receiveHandshake(conn, buffer: Data())
    }

    private func receiveHandshake(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var buf = buffer
            if let data = data {
                print("WS: 收到请求字节 \(data.count)")
                buf.append(data)
            }
            if let error = error {
                print("WS: 接收错误 \(error.localizedDescription)")
            }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buf[..<range.lowerBound], encoding: .utf8) ?? ""
                self?.handleRequest(head, conn: conn)
            } else if error != nil {
                conn.cancel()
            } else if isComplete {
                conn.cancel()
            } else {
                self?.receiveHandshake(conn, buffer: buf)
            }
        }
    }

    private func handleRequest(_ head: String, conn: NWConnection) {
        print("WS: 处理请求：\(head.split(separator: "\r\n").first ?? "")")
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { conn.cancel(); return }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = String(parts[0])
        let rawPath = String(parts[1])
        let pathAndQuery = rawPath.split(separator: "?", maxSplits: 1).map(String.init)
        let path = pathAndQuery[0]
        let query = pathAndQuery.count > 1 ? pathAndQuery[1] : ""

        let headers = Dictionary(
            lines.dropFirst().compactMap { line -> (String, String)? in
                guard let colon = line.range(of: ":") else { return nil }
                let key = line[..<colon.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[colon.upperBound...].trimmingCharacters(in: .whitespaces)
                return (key, value)
            },
            uniquingKeysWith: { first, _ in first }
        )

        if method == "GET", headers["upgrade"]?.lowercased() == "websocket", path == "/stream" {
            // 访问口令校验
            if let token {
                let params = parseQuery(query)
                guard params["token"] == token else {
                    let response = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n"
                    sendHTTPResponse(Data(response.utf8), conn: conn)
                    return
                }
            }
            guard let key = headers["sec-websocket-key"] else { conn.cancel(); return }
            let accept = websocketAccept(key: key)
            print("WS: 升级成功，发送 101")
            // 注意：必须用显式 \r\n 拼 HTTP 头。
            // Swift 多行字符串会吞掉结尾换行，导致空行变成单独的 \r，浏览器会拒绝解析。
            let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            conn.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
                if let error {
                    print("WS: 发送 101 失败 \(error.localizedDescription)")
                } else {
                    print("WS: 101 已发送")
                }
                self?.addClient(conn)
            })
        } else if method == "GET", path == "/" || path == "/index.html" {
            // 页面嵌入"是否需要口令"和应用列表，前端据此显示登录层/切换栏。
            let flag = token == nil ? "false" : "true"
            let appsJSON = "[" + apps.map { Self.jsonString($0) }.joined(separator: ",") + "]"
            let html = viewerHTML
                .replacingOccurrences(of: "__TOKEN_REQUIRED__", with: flag)
                .replacingOccurrences(of: "__APPS__", with: appsJSON)
            let body = Data(html.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\n\r\n"
            var out = Data(header.utf8)
            out.append(body)
            sendHTTPResponse(out, conn: conn)
        } else {
            let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
            sendHTTPResponse(Data(response.utf8), conn: conn)
        }
    }

    /// 发送 HTTP 响应后不能立即 cancel()，否则尾部数据会被丢弃（实测截断）。
    /// 改为保持连接直到客户端关闭，再释放。
    private func sendHTTPResponse(_ data: Data, conn: NWConnection) {
        conn.send(content: data, contentContext: .defaultMessage, isComplete: true,
                  completion: .contentProcessed { [weak self] _ in
            self?.waitForClientClose(conn)
        })
    }

    private func waitForClientClose(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                conn.cancel()
            } else {
                self?.waitForClientClose(conn)
            }
        }
    }

    private func websocketAccept(key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let hash = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        return Data(hash).base64EncodedString()
    }

    private func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                result[kv[0]] = kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1]
            }
        }
        return result
    }

    private func addClient(_ conn: NWConnection) {
        clients[ObjectIdentifier(conn)] = Client(conn: conn)
        print("WS: 客户端已加入，当前 \(clients.count) 个")
        readClientFrames(conn)
    }

    private func removeClient(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        clients.removeValue(forKey: id)
        receiveBuffers.removeValue(forKey: id)
    }

    /// 读取客户端数据并解析 WebSocket 帧（文本/关闭/Ping）。
    private func readClientFrames(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.processClientData(data, conn: conn)
            }
            if error != nil {
                self.removeClient(conn)
            } else if isComplete {
                conn.cancel()
                self.removeClient(conn)
            } else {
                self.readClientFrames(conn)
            }
        }
    }

    private func processClientData(_ data: Data, conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        var buffer = receiveBuffers[id] ?? Data()
        buffer.append(data)
        receiveBuffers[id] = buffer
        parseClientFrames(conn)
    }

    private func parseClientFrames(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        guard var buffer = receiveBuffers[id] else { return }
        defer { receiveBuffers[id] = buffer }

        while buffer.count >= 2 {
            let b0 = buffer[buffer.startIndex]
            let b1 = buffer[buffer.startIndex + 1]
            let opcode = b0 & 0x0F
            let masked = (b1 & 0x80) != 0
            var payloadLength = Int(b1 & 0x7F)
            var headerLength = 2
            if payloadLength == 126 {
                guard buffer.count >= 4 else { return }
                payloadLength = Int(readUInt16(buffer, at: 2))
                headerLength = 4
            } else if payloadLength == 127 {
                guard buffer.count >= 10 else { return }
                payloadLength = Int(readUInt64(buffer, at: 2))
                headerLength = 10
            }
            let maskLength = masked ? 4 : 0
            let total = headerLength + maskLength + payloadLength
            guard buffer.count >= total else { return }

            var payload = Data(buffer[(buffer.startIndex + headerLength + maskLength)...].prefix(payloadLength))
            if masked {
                let maskStart = buffer.startIndex + headerLength
                let mask = [buffer[maskStart], buffer[maskStart + 1], buffer[maskStart + 2], buffer[maskStart + 3]]
                for i in payload.indices {
                    payload[i] ^= mask[i % 4]
                }
            }
            buffer.removeFirst(total)

            switch opcode {
            case 0x1: // text
                if let text = String(data: payload, encoding: .utf8) {
                    handleTextMessage(text, conn: conn)
                }
            case 0x8: // close
                conn.cancel()
                removeClient(conn)
                return
            case 0x9: // ping → pong
                sendPong(payload, conn: conn)
            default:
                break
            }
        }
    }

    /// 文本消息分流：AI 优化 / Key 设置走服务端，其余转发给控制指令处理器。
    private func handleTextMessage(_ text: String, conn: NWConnection) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            let source = clients[ObjectIdentifier(conn)]?.source ?? 0
            onTextMessage?(text, source)
            return
        }

        switch type {
        case "switch":
            guard let index = obj["index"] as? Int, index >= 0, index < sourceCount else {
                sendTextFrame("{\"type\":\"switch_ok\",\"ok\":false,\"error\":\"应用序号无效\"}", to: conn)
                return
            }
            // 实际切流由 CLI 处理（按需停止旧流、启动新窗口流）。
            // 切流完成后由 notifySwitch 广播结果，客户端收到后才高亮切换。
            let source = clients[ObjectIdentifier(conn)]?.source ?? 0
            onTextMessage?(text, source)
        case "setkey":
            let newKey = obj["key"] as? String
            textOptimizer.setKey(newKey)
            KeyStore.save(newKey)
            sendTextFrame("{\"type\":\"key_status\",\"ok\":true,\"hasKey\":\(textOptimizer.hasKey)}", to: conn)
        case "getkey":
            sendTextFrame("{\"type\":\"key_status\",\"ok\":true,\"hasKey\":\(textOptimizer.hasKey)}", to: conn)
        case "ai":
            guard obj["action"] as? String == "optimize", let input = obj["text"] as? String else {
                sendTextFrame("{\"type\":\"ai_result\",\"ok\":false,\"error\":\"参数错误\"}", to: conn)
                return
            }
            guard textOptimizer.hasKey else {
                sendTextFrame("{\"type\":\"ai_result\",\"ok\":false,\"error\":\"未配置 DeepSeek API Key（启动时加 --deepseek-key 或点 ⚙ 设置）\"}", to: conn)
                return
            }
            Task { [weak self] in
                do {
                    let optimized = try await self?.textOptimizer.optimize(input) ?? ""
                    self?.sendTextFrame("{\"type\":\"ai_result\",\"ok\":true,\"text\":\(Self.jsonString(optimized))}", to: conn)
                } catch {
                    self?.sendTextFrame("{\"type\":\"ai_result\",\"ok\":false,\"error\":\(Self.jsonString(error.localizedDescription))}", to: conn)
                }
            }
        default:
            let source = clients[ObjectIdentifier(conn)]?.source ?? 0
            onTextMessage?(text, source)
        }
    }

    private func sendTextFrame(_ string: String, to conn: NWConnection) {
        let payload = Data(string.utf8)
        var out = Data()
        out.append(0x81)
        let n = payload.count
        if n < 126 {
            out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(126)
            out.append(UInt8((n >> 8) & 0xFF))
            out.append(UInt8(n & 0xFF))
        } else {
            out.append(127)
            var big = UInt64(n).bigEndian
            withUnsafeBytes(of: &big) { out.append(contentsOf: $0) }
        }
        out.append(payload)
        conn.send(content: out, completion: .contentProcessed { _ in })
    }

    private static func jsonString(_ string: String) -> String {
        // NSJSONSerialization 顶层必须是数组/字典，所以包一层数组再剥掉括号。
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              var result = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        result.removeFirst()
        result.removeLast()
        return result
    }

    private func sendPong(_ payload: Data, conn: NWConnection) {
        var out = Data()
        out.append(0x8A)
        let n = payload.count
        if n < 126 {
            out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(126)
            out.append(UInt8((n >> 8) & 0xFF))
            out.append(UInt8(n & 0xFF))
        } else {
            out.append(127)
            var big = UInt64(n).bigEndian
            withUnsafeBytes(of: &big) { out.append(contentsOf: $0) }
        }
        out.append(payload)
        conn.send(content: out, completion: .contentProcessed { _ in })
    }

    private func readUInt16(_ buffer: Data, at offset: Int) -> UInt16 {
        UInt16(buffer[buffer.startIndex + offset]) << 8 | UInt16(buffer[buffer.startIndex + offset + 1])
    }

    private func readUInt64(_ buffer: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(buffer[buffer.startIndex + offset + i])
        }
        return value
    }

    // MARK: - 帧发送

    private func sendFrame(_ data: Data, for id: ObjectIdentifier) {
        guard let client = clients[id] else { return }
        client.conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                print("WS: 发送帧失败 \(error.localizedDescription)")
            }
            guard let self, var current = self.clients[id] else { return }
            current.sending = false
            if let next = current.nextFrame {
                current.nextFrame = nil
                self.clients[id] = current
                self.sendFrame(next, for: id)
            } else {
                self.clients[id] = current
            }
        })
    }

    private func encodeFrame(_ payload: Data) -> Data {
        var out = Data()
        out.reserveCapacity(payload.count + 10)
        out.append(0x82) // FIN + 二进制帧
        let n = payload.count
        if n < 126 {
            out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(126)
            out.append(UInt8((n >> 8) & 0xFF))
            out.append(UInt8(n & 0xFF))
        } else {
            out.append(127)
            var bigEndian = UInt64(n).bigEndian
            withUnsafeBytes(of: &bigEndian) { out.append(contentsOf: $0) }
        }
        out.append(payload)
        return out
    }
}
