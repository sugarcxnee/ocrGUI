import Testing
import Foundation
import AppKit
import CoreGraphics
@testable import OCRGUICore

// MARK: - 测试辅助：用 CoreText 渲染确定性测试图

@MainActor
func renderTextImage(_ lines: [(text: String, y: CGFloat)], size: CGSize) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    for line in lines {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 56, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        (line.text as NSString).draw(at: NSPoint(x: 40, y: line.y), withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

// MARK: - VisionEngine

@MainActor
@Test("Vision 引擎识别中英文混合图片：文本、置信度、四点坐标、阅读顺序")
func visionRecognizesChineseAndEnglish() async throws {
    let image = renderTextImage(
        [(text: "Hello OCR 12345", y: 420), (text: "你好世界测试", y: 280)],
        size: CGSize(width: 1000, height: 600))

    let engine = VisionEngine(config: EngineStore.defaultConfigs[0])
    #expect(engine.capabilities.hasLineBoxes)
    #expect(!engine.capabilities.outputsMarkdown)

    let page = try await engine.recognize(image: image, options: RecognizeOptions())

    let text = page.mergedText
    #expect(text.contains("OCR"))
    #expect(text.contains("12345"))
    #expect(text.contains("你好世界"))

    #expect(!page.lines.isEmpty)
    for line in page.lines {
        #expect(line.score > 0.2)
        #expect(line.box.count == 4)
        for pt in line.box {
            #expect(pt.count == 2)
            #expect(pt[0] >= -1 && pt[0] <= CGFloat(image.width) + 1)
            #expect(pt[1] >= -1 && pt[1] <= CGFloat(image.height) + 1)
        }
    }

    // 阅读顺序：第一行的 y 不大于最后一行（自上而下）
    if let first = page.lines.first?.box.first, let last = page.lines.last?.box.first {
        #expect(first[1] <= last[1] + 1)
    }

    #expect(page.width == image.width)
    #expect(page.height == image.height)
    #expect(page.pageNumber == 1)
}

@MainActor
@Test("Vision 引擎健康检查始终就绪")
func visionHealthAlwaysReady() async {
    let engine = VisionEngine(config: EngineStore.defaultConfigs[0])
    let health = await engine.healthCheck()
    #expect(health == .ready)
}

// MARK: - EngineFactory

@Test("工厂按 kind 构造引擎；未实现类型抛错")
func factoryBuildsVision() throws {
    let vision = EngineConfig(id: "vision", name: "V", kind: .builtinVision, enabled: true,
                              baseURL: nil, model: nil, prompt: nil, apiKey: nil,
                              timeout: 60, launch: nil, notes: nil)
    let engine = try EngineFactory.make(config: vision)
    #expect(engine is VisionEngine)

    let other = EngineConfig(id: "x", name: "X", kind: .jsonHTTP, enabled: true,
                             baseURL: "http://127.0.0.1:1", model: nil, prompt: nil, apiKey: nil,
                             timeout: 60, launch: nil, notes: nil)
    #expect(throws: EngineFactoryError.self) { try EngineFactory.make(config: other) }
}

// MARK: - ImageIO 工具

@Test("CGImage ↔ PNG Data 往返；缩略图限制最大边")
func imageIOThumbnail() throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1000,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = try #require(rep.cgImage)

    let png = try #require(ImageTools.pngData(from: cg))
    let roundtrip = try #require(ImageTools.cgImage(from: png))
    #expect(roundtrip.width == 2000)

    let thumbPNG = try #require(ImageTools.thumbnailPNG(from: cg, maxPixel: 320))
    let thumb = try #require(ImageTools.cgImage(from: thumbPNG))
    #expect(max(thumb.width, thumb.height) == 320)
    #expect(thumb.width == 320 && thumb.height == 160)
}
