import Foundation
import CoreVideo
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

public enum JPEGEncoder {
    /// 共享 CIContext，避免每帧重建（CIContext 可跨线程使用）。
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// CVPixelBuffer → JPEG Data。
    /// 优先 VideoToolbox 快速路径；失败时回退 CoreImage 渲染，兼容各种像素格式。
    public static func encode(_ pixelBuffer: CVPixelBuffer, quality: Double) -> Data? {
        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        if status == noErr, let image = cgImage {
            return encode(image, quality: quality)
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let rendered = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return encode(rendered, quality: quality)
    }

    /// CGImage → JPEG Data。
    public static func encode(_ image: CGImage, quality: Double) -> Data? {
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }
}
