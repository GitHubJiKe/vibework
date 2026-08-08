// 生成 VibePilot 主屏幕图标（180x180 / 512x512 PNG）。
// 用法：swift scripts/gen-icon.swift
import AppKit

func makeIcon(size: Int, path: String) {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // 圆角裁剪
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.22
    let path2 = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path2.addClip()

    // 深蓝 → 紫渐变背景
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.82, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.16, blue: 0.80, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -50)

    // 大 "V" 字母
    let vText = NSAttributedString(string: "V", attributes: [
        .font: NSFont.systemFont(ofSize: s * 0.56, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    let vs = vText.size()
    vText.draw(at: NSPoint(x: (s - vs.width) / 2, y: (s - vs.height) / 2 - s * 0.06))

    // 底部脉冲波形（三条递增的弧线）
    let wave = NSBezierPath()
    wave.lineWidth = s * 0.045
    wave.lineCapStyle = .round
    let baseY = s * 0.18
    for (i, w) in [0.20, 0.34, 0.48].enumerated() {
        let barW = s * CGFloat(w)
        let x = (s - barW) / 2
        let y = baseY + CGFloat(i) * s * 0.14
        wave.move(to: NSPoint(x: x, y: y))
        wave.line(to: NSPoint(x: x + barW, y: y))
    }
    NSColor.white.withAlphaComponent(0.85).setStroke()
    wave.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("icon generation failed: \(path)")
        return
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("OK: \(path) (\(size)x\(size))")
}

makeIcon(size: 180, path: "web/icon-180.png")
makeIcon(size: 512, path: "web/icon-512.png")
