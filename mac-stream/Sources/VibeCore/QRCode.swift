import Foundation
import CoreImage
import CoreGraphics

/// 二维码生成：CoreImage 渲染后转成终端可显示的字符画（无需任何第三方库）。
public enum QRCode {
    /// 生成终端二维码字符画。
    /// 用 █ / ▀ / ▄ / 空格 四个字符表示 2x1 像素单元，任何终端都能显示。
    public static func terminalQRCode(from string: String, quietZone: Int = 2) -> String? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        // CIQRCodeGenerator 输出的每个模块正好 1 像素
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CIContext()
        context.render(ciImage, toBitmap: &pixels, rowBytes: width * 4,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        func isBlack(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            // 二维码是黑白色，取亮度（alpha 通道优先）
            let alpha = pixels[(y * width + x) * 4 + 3]
            let red = pixels[(y * width + x) * 4]
            return alpha >= 128 && red < 128
        }

        var lines: [String] = []
        let blank = String(repeating: " ", count: width + quietZone * 2)
        for _ in 0..<quietZone {
            lines.append(blank)
        }
        var row = 0
        while row < height {
            var line = String(repeating: " ", count: quietZone)
            for col in 0..<width {
                let top = isBlack(col, row)
                let bottom = isBlack(col, row + 1)
                switch (top, bottom) {
                case (true, true): line += "█"
                case (true, false): line += "▀"
                case (false, true): line += "▄"
                case (false, false): line += " "
                }
            }
            line += String(repeating: " ", count: quietZone)
            lines.append(line)
            row += 2
        }
        for _ in 0..<quietZone {
            lines.append(blank)
        }
        return lines.joined(separator: "\n")
    }
}
