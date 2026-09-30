import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import OCRGUICore

// MARK: - 测试辅助

/// 用 CoreGraphics 生成多页 PDF（每页白底 + 页码文本），返回文件 URL
func makeTestPDF(pages: [(CGFloat, CGFloat)], dir: URL) throws -> URL {
    let url = dir.appendingPathComponent("test-\(UUID().uuidString).pdf")
    var mediaBox = CGRect(origin: .zero, size: CGSize(width: 200, height: 100))
    guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    for (index, size) in pages.enumerated() {
        ctx.beginPDFPage(nil)
        // 画页码（数字，避免字体问题）
        let attributed = NSAttributedString(
            string: "\(index + 1)",
            attributes: [.font: CTFontCreateWithName("Helvetica-Bold" as CFString, 40, nil)])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: 20, y: 40)
        CTLineDraw(line, ctx)
        _ = size
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return url
}

/// 纯色 CGImage
func solidImage(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

// MARK: - PDFRenderer

@Suite(.serialized)
struct PDFRendererTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("渲染多页 PDF：页数、页码、按 DPI 缩放的像素尺寸")
    func rendersAllPagesAtDPI() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try makeTestPDF(pages: [(200, 100), (200, 100)], dir: dir)
        #expect(PDFRenderer.pageCount(url: url) == 2)

        let pages = try #require(try PDFRenderer.render(url: url, dpi: 144))
        #expect(pages.count == 2)
        // 200x100pt @144dpi = 400x200px
        #expect(pages[0].image.width == 400)
        #expect(pages[0].image.height == 200)
        #expect(pages[0].pageNumber == 1)
        #expect(pages[1].pageNumber == 2)
        #expect(pages[0].totalPages == 2)
    }

    @Test("加密/损坏 PDF 抛错")
    func invalidPDFThrows() {
        let bad = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).pdf")
        try? Data("not a pdf".utf8).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        #expect(PDFRenderer.pageCount(url: bad) == nil)
    }
}

// MARK: - FileScanner

struct FileScannerTests {

    @Test("递归扫描文件夹：仅图片与 PDF，按路径排序")
    func scansRecursively() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["a.png", "b/c.jpg", "b/B2.tiff", "b/note.txt", "b/c.pdf", ".hidden.png"] {
            try Data([0]).write(to: dir.appendingPathComponent(name))
        }

        let urls = FileScanner.scan(folder: dir)
        let names = urls.map(\.lastPathComponent)
        #expect(names == ["a.png", "B2.tiff", "c.jpg", "c.pdf"])
    }

    @Test("单文件类型判定")
    func classifiesFiles() {
        #expect(FileScanner.kind(forExtension: "pdf") == .pdf)
        #expect(FileScanner.kind(forExtension: "png") == .image)
        #expect(FileScanner.kind(forExtension: "txt") == nil)
        #expect(FileScanner.kind(forExtension: "PDF") == .pdf)
    }
}
