import Testing
import Foundation
@testable import OCRGUICore

// MARK: - 预览布局数学（修复"放大后只显示一部分/不能滚动"的回归测试）

struct PreviewLayoutTests {

    private let image = CGSize(width: 1000, height: 1600)   // 典型 200DPI A5 书页
    private let viewport = CGSize(width: 500, height: 600)  // 预览窗格

    @Test("适应（zoom=1）：完整显示且不超出可视区")
    func fitMode() {
        let layout = PreviewLayout(imageSize: image, viewport: viewport, zoom: 1, actualPixels: false)
        // 等比适配：高度受限 600 → scale 0.375 → 375×600
        #expect(abs(layout.scale - 0.375) < 0.001)
        #expect(layout.drawn.width <= viewport.width + 0.5)
        #expect(layout.drawn.height <= viewport.height + 0.5)
        // 内容比可视区小 → 撑满可视区（居中显示）
        #expect(layout.extent.width == viewport.width)
        #expect(layout.extent.height == viewport.height)
    }

    @Test("放大 3×：内容尺寸 = 适配尺寸×3，滚动范围=内容尺寸（可完整滚动查看）")
    func zoomed() {
        let fit = PreviewLayout(imageSize: image, viewport: viewport, zoom: 1, actualPixels: false)
        let layout = PreviewLayout(imageSize: image, viewport: viewport, zoom: 3, actualPixels: false)
        #expect(abs(layout.drawn.width - fit.drawn.width * 3) < 0.5)
        #expect(abs(layout.drawn.height - fit.drawn.height * 3) < 0.5)
        // 滚动范围必须等于放大后的内容，而不是可视区
        #expect(layout.extent.width == layout.drawn.width)
        #expect(layout.extent.height == layout.drawn.height)
        // 偏移为 0（内容大于可视区时从左上角开始）
        #expect(layout.contentOffset == .zero)
    }

    @Test("1:1 实际像素：内容尺寸 = 图像像素尺寸")
    func actualPixels() {
        let layout = PreviewLayout(imageSize: image, viewport: viewport, zoom: 1, actualPixels: true)
        #expect(layout.scale == 1.0)
        #expect(layout.drawn.width == 1000)
        #expect(layout.drawn.height == 1600)
        #expect(layout.extent == layout.drawn)
    }

    @Test("缩小时内容不小于下限：extent 不小于可视区（保证居中不留黑洞）")
    func tinyImageCentered() {
        let layout = PreviewLayout(imageSize: CGSize(width: 100, height: 80),
                                   viewport: viewport, zoom: 1, actualPixels: false)
        #expect(layout.drawn.width <= 500)
        #expect(layout.extent == viewport)
        // 居中偏移
        #expect(layout.contentOffset.x == (viewport.width - layout.drawn.width) / 2)
    }
}
