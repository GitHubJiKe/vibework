import AppKit
import CoreGraphics

/// 演示画面：不依赖屏幕捕获，用于联调推流链路。
public enum Demo {
    public static func makeImage(frame: Int) -> CGImage {
        let width = 480, height = 300
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let hue = CGFloat(frame % 100) / 100.0
        ctx.setFillColor(NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let x = CGFloat((frame * 9) % (width + 60)) - 30
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: x, y: 110, width: 50, height: 50))
        return ctx.makeImage()!
    }
}
