import SwiftUI
import AppKit
import CoreImage

/// 生成二维码 NSImage（macOS 原生 CoreImage，零第三方依赖）。
func makeQRCode(from string: String, size: CGFloat) -> NSImage? {
    let data = Data(string.utf8)
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let ciImage = filter.outputImage else { return nil }

    // QR 码默认只有约 23x23 点，按目标尺寸放大
    let scale = size / ciImage.extent.width
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

/// 二维码弹窗：手机相机扫码直接打开访问地址。
struct QRCodeView: View {
    let url: String

    var body: some View {
        VStack(spacing: 14) {
            Text("手机扫码访问")
                .font(.headline)
            if let image = makeQRCode(from: url, size: 220) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
            } else {
                Text("二维码生成失败")
                    .foregroundStyle(.secondary)
            }
            Text(url)
                .font(.system(.body, design: .monospaced))
            Text("同一 Wi-Fi 下，用 iPhone 相机扫码即可打开")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }
}
