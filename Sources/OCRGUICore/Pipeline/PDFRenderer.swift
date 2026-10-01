import Foundation
import CoreGraphics

/// PDF 逐页渲染（纯 CoreGraphics，处理页面旋转；加密 PDF 不支持，与 webUI 策略一致）
public enum PDFRenderer {
    public static func pageCount(url: URL) -> Int? {
        guard let doc = CGPDFDocument(url as CFURL),
              doc.numberOfPages > 0,
              !doc.isEncrypted else { return nil }
        return doc.numberOfPages
    }

    public static func render(url: URL, dpi: CGFloat) throws -> [PageLoad] {
        guard let doc = CGPDFDocument(url as CFURL) else {
            throw EngineError.imageDecodeFailed
        }
        if doc.isEncrypted {
            throw EngineError.imageDecodeFailed
        }
        let total = doc.numberOfPages
        guard total > 0 else { throw EngineError.imageDecodeFailed }

        var result: [PageLoad] = []
        for index in 1...total {
            guard let page = doc.page(at: index) else { continue }
            if let image = renderPage(page, dpi: dpi) {
                result.append(PageLoad(image: image, pageNumber: index, totalPages: total))
            }
        }
        return result
    }

    /// 只渲染某一页（1-based，越界返回 nil）——大 PDF 页面预览用，避免整本渲染
    public static func renderPage(url: URL, page: Int, dpi: CGFloat) -> PageLoad? {
        guard let doc = CGPDFDocument(url as CFURL), !doc.isEncrypted,
              page >= 1, page <= doc.numberOfPages,
              let pdfPage = doc.page(at: page),
              let image = renderPage(pdfPage, dpi: dpi) else {
            return nil
        }
        return PageLoad(image: image, pageNumber: page, totalPages: doc.numberOfPages)
    }

    private static func renderPage(_ page: CGPDFPage, dpi: CGFloat) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        let scale = dpi / 72.0
        let rotation = page.rotationAngle

        var width = box.width * scale
        var height = box.height * scale
        if rotation == 90 || rotation == 270 {
            swap(&width, &height)
        }
        let pixelsW = max(1, Int(width.rounded()))
        let pixelsH = max(1, Int(height.rounded()))

        guard let ctx = CGContext(data: nil, width: pixelsW, height: pixelsH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelsW, height: pixelsH))

        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        switch rotation {
        case 90:
            ctx.translateBy(x: box.height, y: 0)
            ctx.rotate(by: .pi / 2)
            ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        case 180:
            ctx.translateBy(x: box.width, y: box.height)
            ctx.rotate(by: .pi)
            ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        case 270:
            ctx.translateBy(x: 0, y: box.width)
            ctx.rotate(by: -.pi / 2)
            ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        default:
            ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        }
        ctx.drawPDFPage(page)
        ctx.restoreGState()

        return ctx.makeImage()
    }
}
