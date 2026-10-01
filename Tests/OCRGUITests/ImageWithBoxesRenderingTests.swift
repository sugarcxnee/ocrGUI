import Testing
import Foundation
import SwiftUI
import AppKit
@testable import OCRGUICore

// MARK: - 预览组件真实渲染验证（修复"放大后只显示一部分"的回归测试）

/// 用 NSHostingView + 真实 SwiftUI 布局引擎测量 ImageWithBoxes 的实际内容尺寸。
/// 断言：zoom>1 时内容大于可视区（可滚动完整查看）；zoom=1 时恰好适配。
@MainActor
struct ImageWithBoxesRenderingTests {

    /// 生成 2000×3200 的测试页（200DPI 书页量级）
    private func makePageImage() -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 3200,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 2000, height: 3200).fill()
        NSColor.black.setFill()
        for row in 0..<40 {
            NSRect(x: 100, y: 3000 - row * 75, width: 1400, height: 30).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(cgImage: rep.cgImage!, size: NSSize(width: 2000, height: 3200))
        return image
    }

    /// 在固定可视区（700×500）内布局组件，返回其真实内容尺寸
    private func measureContentSize(zoom: CGFloat, actualPixels: Bool) -> CGSize {
        final class SizeBox: @unchecked Sendable {
            var size: CGSize = .zero
        }
        let box = SizeBox()
        let page = OcrPage(pageNumber: 1, width: 2000, height: 3200,
                           lines: [OcrLine(text: "行", score: 1, box: [[100, 100], [1500, 100], [1500, 130], [100, 130]])],
                           markdown: nil)

        let hosting = NSHostingView(
            rootView: GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    ImageWithBoxes(nsImage: makePageImage(), page: page,
                                   showBoxes: true, zoom: zoom,
                                   viewport: geo.size, actualPixels: actualPixels)
                        .background(
                            GeometryReader { inner in
                                Color.clear
                                    .onAppear { box.size = inner.size }
                                    .onChange(of: inner.size) { _, newValue in box.size = newValue }
                            }
                        )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: 700, height: 500)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        hosting.layoutSubtreeIfNeeded()
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        // RunLoop 跑一拍，让 onAppear/onChange 尺寸回调落地
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return box.size
    }

    @Test("适应（zoom=1）：内容尺寸恰为可视区 700×500（完整可见，无滚动）")
    func fitRendersViewportSized() {
        let size = measureContentSize(zoom: 1, actualPixels: false)
        #expect(abs(size.width - 700) < 2, "实际内容宽 \(size.width)")
        #expect(abs(size.height - 500) < 2, "实际内容高 \(size.height)")
    }

    @Test("放大 3×：内容大于可视区（可滚动查看整页，修复只显示一部分）")
    func zoomedContentExceedsViewport() {
        let size = measureContentSize(zoom: 3, actualPixels: false)
        // 适配 scale = min(700/2000, 500/3200) = 0.15625；×3 = 0.46875
        // 内容 = 2000×0.46875 = 937.5 宽、3200×0.46875 = 1500 高（都 > 可视区）
        #expect(size.width > 700 + 100, "放大后内容宽仅 \(size.width)，应 ≈937")
        #expect(size.height > 500 + 100, "放大后内容高仅 \(size.height)，应 =1500")
        #expect(abs(size.width - 937.5) < 3, "内容宽 \(size.width)，应 ≈937.5")
        #expect(abs(size.height - 1500) < 3, "内容高 \(size.height)，应 =1500")
    }

    @Test("1:1 实际像素：内容 = 图像像素尺寸 2000×3200")
    func actualPixelsRendersFullSize() {
        let size = measureContentSize(zoom: 1, actualPixels: true)
        #expect(abs(size.width - 2000) < 3, "1:1 内容宽 \(size.width)")
        #expect(abs(size.height - 3200) < 3, "1:1 内容高 \(size.height)")
    }
}
