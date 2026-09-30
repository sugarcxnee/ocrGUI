import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// CGImage 编解码与缩放工具（纯 CoreGraphics，核心库不依赖 AppKit）
public enum ImageTools {
    public static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    public static func pngData(from cg: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// 等比缩放，使最长边不超过 maxPixel（只缩小不放大）
    public static func resized(_ cg: CGImage, maxPixel: CGFloat) -> CGImage {
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let scale = min(1, maxPixel / max(w, h))
        let newW = max(1, Int((w * scale).rounded()))
        let newH = max(1, Int((h * scale).rounded()))
        guard scale < 1 else { return cg }

        let ctx = CGContext(data: nil, width: newW, height: newH,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cg.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .high
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx?.makeImage() ?? cg
    }

    public static func thumbnailPNG(from cg: CGImage, maxPixel: CGFloat = 320) -> Data? {
        pngData(from: resized(cg, maxPixel: maxPixel))
    }
}
