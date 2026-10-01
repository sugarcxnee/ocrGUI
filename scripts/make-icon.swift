// swift scripts/make-icon.swift <输出目录>
// 生成 macOS 应用图标（icon_128x128.png … icon_512x512@2x.png）+ icns
// 设计：深蓝紫渐变底 + 圆角超椭圆 + 橙色取景框四角 + 白色文字行（第二行被"识别"为高亮）
import AppKit
import CoreGraphics

let size = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"

// ── 画布 ──
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// ── 背景：macOS 风格连续圆角方形 + 对角渐变 ──
let inset: CGFloat = 60                      // macOS 图标四周留白比例
let tile = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let corner: CGFloat = tile.width * 0.225     // squircle 近似圆角
let bg = NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner)

let gradient = NSGradient(colors: [
    NSColor(red: 0.16, green: 0.19, blue: 0.38, alpha: 1),   // 深蓝
    NSColor(red: 0.28, green: 0.16, blue: 0.45, alpha: 1),   // 紫罗兰
])!
gradient.draw(in: bg, angle: -70)

// 顶部柔光（立体感）
ctx.saveGState()
bg.addClip()
// 顶部柔光：全幅绘制避免中缝硬边（渐变止于 55% 处自然衰减）
let gloss = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.13),
    NSColor.white.withAlphaComponent(0.03),
    NSColor.white.withAlphaComponent(0.0),
])!
gloss.draw(in: tile, angle: 90)
ctx.restoreGState()

// ── 取景框（四角括号，橙色，OCR 核心隐喻）──
let accent = NSColor(red: 1.0, green: 0.58, blue: 0.20, alpha: 1)   // 暖橙
let frameRect = NSRect(x: tile.minX + tile.width * 0.18,
                       y: tile.minY + tile.height * 0.22,
                       width: tile.width * 0.64,
                       height: tile.height * 0.56)
let armLen: CGFloat = frameRect.width * 0.16
let lineW: CGFloat = tile.width * 0.045
ctx.setStrokeColor(accent.cgColor)
ctx.setLineWidth(lineW)
ctx.setLineCap(.round)
for (cx, cy, dx, dy) in [(frameRect.minX, frameRect.maxY, CGFloat(1), CGFloat(-1)),
                         (frameRect.maxX, frameRect.maxY, CGFloat(-1), CGFloat(-1)),
                         (frameRect.minX, frameRect.minY, CGFloat(1), CGFloat(1)),
                         (frameRect.maxX, frameRect.minY, CGFloat(-1), CGFloat(1))] {
    ctx.move(to: CGPoint(x: cx + CGFloat(dx) * armLen, y: cy))
    ctx.addLine(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx, y: cy + CGFloat(dy) * armLen))
    ctx.strokePath()
}

// ── 文字行：三条圆角短横条，第二条为"正在被识别"的橙色高亮 ──
func bar(_ rect: CGRect, color: NSColor) {
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
}
let barH = frameRect.height * 0.10
let bars: [(NSRect, NSColor)] = [
    (NSRect(x: frameRect.minX + frameRect.width * 0.10, y: frameRect.maxY - frameRect.height * 0.26,
            width: frameRect.width * 0.62, height: barH), NSColor.white.withAlphaComponent(0.92)),
    (NSRect(x: frameRect.minX + frameRect.width * 0.10, y: frameRect.midY - barH / 2,
            width: frameRect.width * 0.78, height: barH), accent),
    (NSRect(x: frameRect.minX + frameRect.width * 0.10, y: frameRect.minY + frameRect.height * 0.16,
            width: frameRect.width * 0.48, height: barH), NSColor.white.withAlphaComponent(0.68)),
]
for (rect, color) in bars {
    ctx.setFillColor(color.cgColor)
    bar(rect, color: color)
}

// ── 扫描线：横贯取景框的亮线 + 微光晕（"正在扫描"动效的静态表达）──
let scanY = frameRect.midY + frameRect.height * 0.08
ctx.saveGState()
bg.addClip()
let glow = NSColor(red: 1.0, green: 0.75, blue: 0.35, alpha: 0.14)
ctx.setFillColor(glow.cgColor)
ctx.fill(NSRect(x: frameRect.minX + frameRect.width * 0.06, y: scanY - lineW * 1.2,
                width: frameRect.width * 0.88, height: lineW * 2.4))
ctx.setStrokeColor(NSColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 0.95).cgColor)
ctx.setLineWidth(lineW * 0.45)
ctx.move(to: CGPoint(x: frameRect.minX - lineW, y: scanY))
ctx.addLine(to: CGPoint(x: frameRect.maxX + lineW, y: scanY))
ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

// ── 输出全套尺寸 ──
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs {
    let scaled = NSImage(size: NSSize(width: px, height: px), flipped: false) { _ in
        NSGraphicsContext.current?.cgContext.draw(rep.cgImage!, in: NSRect(x: 0, y: 0, width: px, height: px))
        return true
    }
    let tiff = scaled.tiffRepresentation!
    let imageRep = NSBitmapImageRep(data: tiff)!
    let png = imageRep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("已生成 \(specs.count) 个尺寸 → \(outDir)/")
print("合并 icns：iconutil -c icns \(outDir) -o AppIcon.icns")
