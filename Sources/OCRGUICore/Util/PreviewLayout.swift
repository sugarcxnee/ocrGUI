import Foundation
import CoreGraphics

/// 预览区布局数学：给定图像尺寸/可视区/缩放，计算显示尺寸、滚动范围与居中偏移。
/// 修复要点：放大后 extent（ScrollView 的内容范围）必须等于放大后的内容尺寸，
/// 否则只显示一部分且无法滚动。
public struct PreviewLayout: Equatable, Sendable {
    /// 最终缩放系数（实际像素 = 图像像素 × scale）
    public let scale: CGFloat
    /// 图像显示尺寸
    public let drawn: CGSize
    /// ScrollView 内容范围（= max(可视区, 显示尺寸)：小图撑满居中，大图可滚动）
    public let extent: CGSize
    /// 图像在内容范围中的偏移（小于可视区时居中）
    public let contentOffset: CGPoint

    public init(imageSize: CGSize, viewport: CGSize, zoom: CGFloat, actualPixels: Bool) {
        let fitScale = min(viewport.width / imageSize.width,
                           viewport.height / imageSize.height)
        let resolvedScale: CGFloat = actualPixels ? 1.0 : fitScale * zoom
        scale = resolvedScale
        drawn = CGSize(width: imageSize.width * resolvedScale,
                       height: imageSize.height * resolvedScale)
        extent = CGSize(width: max(viewport.width, drawn.width),
                        height: max(viewport.height, drawn.height))
        contentOffset = CGPoint(x: (extent.width - drawn.width) / 2,
                                y: (extent.height - drawn.height) / 2)
    }
}
