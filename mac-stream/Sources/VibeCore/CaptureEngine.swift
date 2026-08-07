import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics

/// ScreenCaptureKit 窗口捕获引擎。
public final class CaptureEngine: NSObject {
    public typealias FrameHandler = (CVPixelBuffer) -> Void

    public enum CaptureError: LocalizedError {
        case timeout
        case unsupported
        public var errorDescription: String? {
            switch self {
            case .timeout:
                return "等待屏幕内容超时（请确认已授予屏幕录制权限）"
            case .unsupported:
                return "该功能需要 macOS 14+"
            }
        }
    }

    private var stream: SCStream?
    private let onFrame: FrameHandler
    private let queue = DispatchQueue(label: "vibework.capture", qos: .userInteractive)
    private var firstBufferLogged = false
    private var lastLoggedStatus: SCFrameStatus?
    private var noImageBufferLogged = false
    private var streamConfig = SCStreamConfiguration()
    private var nudgeToggle = false

    /// 一次性整屏截图（诊断用）。正常返回图像；如果显示器熄屏/锁屏，可能返回黑图或失败。
    public static func snapshot(display: SCDisplay, maxWidth: Int) async throws -> CGImage? {
        guard #available(macOS 14.0, *) else { throw CaptureError.unsupported }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = min(2.0, Double(maxWidth) / Double(max(1, display.width)))
        config.width = max(1, Int(Double(display.width) * scale))
        config.height = max(1, Int(Double(display.height) * scale))
        config.showsCursor = true
        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    public init(onFrame: @escaping FrameHandler) {
        self.onFrame = onFrame
        super.init()
    }

    /// 列出当前可捕获的窗口（按 App 名排序）。
    /// 列出当前可捕获的窗口（按 App 名排序）。加了超时保护，
    /// 避免权限未授予时 API 一直挂起。
    public static func availableWindows(timeout: TimeInterval = 8) async throws -> [SCWindow] {
        try await withThrowingTaskGroup(of: [SCWindow].self) { group in
            group.addTask {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return content.windows
                    .filter { window in
                        guard let app = window.owningApplication else { return false }
                        let name = app.applicationName
                        let title = window.title ?? ""
                        // 过滤桌面背景/程序坞等无效窗口
                        if name.isEmpty || name == "程序坞" || name == "Dock" { return false }
                        if title.contains("Wallpaper") || title.contains("Backdrop") || title.contains("Backstop") { return false }
                        return window.frame.width >= 100 && window.frame.height >= 100
                    }
                    .sorted { a, b in
                        let an = a.owningApplication?.applicationName ?? ""
                        let bn = b.owningApplication?.applicationName ?? ""
                        if an == bn { return (a.title ?? "") < (b.title ?? "") }
                        return an < bn
                    }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw CaptureError.timeout
            }
            defer { group.cancelAll() }
            guard let windows = try await group.next() else { throw CaptureError.timeout }
            return windows
        }
    }

    /// 列出当前显示器（用于 --screen 整屏捕获诊断）。
    public static func availableDisplays(timeout: TimeInterval = 8) async throws -> [SCDisplay] {
        try await withThrowingTaskGroup(of: [SCDisplay].self) { group in
            group.addTask {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return content.displays
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw CaptureError.timeout
            }
            defer { group.cancelAll() }
            guard let displays = try await group.next() else { throw CaptureError.timeout }
            return displays
        }
    }

    /// 开始捕获指定窗口。maxWidth 控制输出宽度（像素），按比例缩放。
    public func start(window: SCWindow, maxWidth: Int) async throws {
        let scale = min(2.0, Double(maxWidth) / Double(max(1, Int(window.frame.width))))
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = false
        config.queueDepth = 4
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
        streamConfig = config

        let app = window.owningApplication?.applicationName ?? "?"
        let title = window.title ?? ""
        print("已开始捕获窗口：\(app) — \(title)（windowID=\(window.windowID)，\(config.width)x\(config.height)px）")
    }

    /// 开始捕获整个显示器（用于诊断窗口捕获不出帧的情况，也可直接当兜底方案）。
    public func start(display: SCDisplay, maxWidth: Int) async throws {
        let scale = min(2.0, Double(maxWidth) / Double(max(1, display.width)))
        let config = SCStreamConfiguration()
        config.width = max(1, Int(Double(display.width) * scale))
        config.height = max(1, Int(Double(display.height) * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = false
        config.queueDepth = 4
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
        streamConfig = config

        print("已开始捕获整屏（\(config.width)x\(config.height)px）")
    }

    /// 屏幕画面完全静止时 ScreenCaptureKit 不产生新帧；
    /// 通过微调 minimumFrameInterval 触发系统重发一帧（已知的有效做法）。
    public func nudgeForIdleFrame() {
        guard let stream else { return }
        nudgeToggle.toggle()
        let config = SCStreamConfiguration()
        config.width = streamConfig.width
        config.height = streamConfig.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: nudgeToggle ? 29 : 31)
        config.showsCursor = true
        config.capturesAudio = false
        config.queueDepth = streamConfig.queueDepth
        config.pixelFormat = streamConfig.pixelFormat
        stream.updateConfiguration(config) { _ in }
    }

    public func stop() async {
        guard let s = stream else { return }
        try? await s.stopCapture()
        stream = nil
    }
}

extension CaptureEngine: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let status = frameStatus(from: sampleBuffer)
        if status != lastLoggedStatus {
            lastLoggedStatus = status
            print("捕获帧状态：\(statusName(status))")
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if !noImageBufferLogged {
                noImageBufferLogged = true
                print("捕获帧回调偶有无图像缓冲（配置刷新帧，属正常现象，不影响画面）")
            }
            return
        }
        if !firstBufferLogged {
            firstBufferLogged = true
            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            print("捕获到首帧图像：\(width)x\(height)，像素格式 0x\(String(format: "%08x", format))")
        }
        onFrame(pixelBuffer)
    }

    private func frameStatus(from sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let value = CMGetAttachment(sampleBuffer, key: SCStreamFrameInfo.status as CFString, attachmentModeOut: nil) as? NSNumber else {
            return nil
        }
        return SCFrameStatus(rawValue: value.intValue)
    }

    private func statusName(_ status: SCFrameStatus?) -> String {
        guard let status else { return "未知/无状态标记" }
        switch status {
        case .complete: return "Complete（新帧）"
        case .idle: return "Idle（画面无变化）"
        case .blank: return "Blank（显示器已熄屏/黑屏！）"
        case .suspended: return "Suspended（捕获被挂起）"
        case .started: return "Started（流启动）"
        case .stopped: return "Stopped（流停止）"
        @unknown default: return "未知"
        }
    }
}

extension CaptureEngine: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("捕获意外停止：\(error.localizedDescription)")
    }

    @available(macOS 15.2, *)
    public func streamDidBecomeActive(_ stream: SCStream) {
        print("捕获流已激活（被捕获窗口在屏幕上可见）")
    }

    @available(macOS 15.2, *)
    public func streamDidBecomeInactive(_ stream: SCStream) {
        print("⚠️ 捕获流失活：被捕获的窗口可能已关闭/最小化/移到其他桌面")
    }
}
