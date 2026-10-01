import SwiftUI
import CoreGraphics

/// 等比显示原图（尺寸由 PreviewLayout 计算：extent ≥ 可视区，放大后可滚动）；
/// showBoxes 时把页面坐标框（像素、左上原点）映射到显示区域
public struct ImageWithBoxes: View {
    public let nsImage: NSImage?
    public let page: OcrPage?
    public let showBoxes: Bool
    public var zoom: CGFloat = 1
    public var viewport: CGSize = CGSize(width: 800, height: 600)
    /// 1 渲染像素 = 1 屏幕像素（忽略 zoom 倍率）
    public var actualPixels: Bool = false

    public init(nsImage: NSImage?, page: OcrPage?, showBoxes: Bool,
                zoom: CGFloat = 1, viewport: CGSize = CGSize(width: 800, height: 600),
                actualPixels: Bool = false) {
        self.nsImage = nsImage
        self.page = page
        self.showBoxes = showBoxes
        self.zoom = zoom
        self.viewport = viewport
        self.actualPixels = actualPixels
    }

    public var body: some View {
        if let nsImage, nsImage.size.width > 0, nsImage.size.height > 0 {
            let imageSize = CGSize(width: nsImage.size.width, height: nsImage.size.height)
            let layout = PreviewLayout(imageSize: imageSize, viewport: viewport,
                                       zoom: zoom, actualPixels: actualPixels)
            ZStack(alignment: .topLeading) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.drawn.width, height: layout.drawn.height)
                    .offset(x: layout.contentOffset.x, y: layout.contentOffset.y)
                if showBoxes, let page, page.width > 0, page.height > 0 {
                    ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                        let normalized = normalizedRect(of: line, in: page)
                        Rectangle()
                            .stroke(Color.orange, lineWidth: 1.5)
                            .background(Color.orange.opacity(0.08))
                            .frame(width: normalized.width * layout.drawn.width,
                                   height: normalized.height * layout.drawn.height)
                            .offset(x: layout.contentOffset.x + normalized.minX * layout.drawn.width,
                                    y: layout.contentOffset.y + normalized.minY * layout.drawn.height)
                    }
                }
            }
            .frame(width: layout.extent.width, height: layout.extent.height)
        } else {
            VStack {
                Image(systemName: "photo").font(.title)
                Text("原文件不可用（剪贴板/已移动的文件仅保留缩略图）")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 四点框（可能旋转）取外接矩形；坐标从左上原点像素归一化到 0-1
    private func normalizedRect(of line: OcrLine, in page: OcrPage) -> CGRect {
        let xs = line.box.map { $0.count > 0 ? $0[0] : 0 }
        let ys = line.box.map { $0.count > 1 ? $0[1] : 0 }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .zero }
        let x = minX / Double(page.width)
        let y = minY / Double(page.height)
        let w = max(0.002, (maxX - minX) / Double(page.width))
        let h = max(0.002, (maxY - minY) / Double(page.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
