import Foundation
import Vision

/// 系统 Vision 框架引擎：零配置、完全离线、中英文行级识别（accurate 模式）。
public struct VisionEngine: OCREngine {
    public let config: EngineConfig
    public let capabilities = EngineCapabilities(hasLineBoxes: true, outputsMarkdown: false)

    public init(config: EngineConfig) {
        self.config = config
    }

    public func healthCheck() async -> EngineHealth {
        .ready
    }

    public func recognize(image: CGImage, options: RecognizeOptions) async throws -> OcrPage {
        try Task.checkCancellation()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // 中文不支持语言纠正，关闭以保持原文
        request.usesLanguageCorrection = false
        request.recognitionLanguages = options.languages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    cont.resume()
                } catch {
                    cont.resume(throwing: EngineError.requestFailed(error.localizedDescription))
                }
            }
        }
        try Task.checkCancellation()

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let observations = request.results ?? []

        var lines: [OcrLine] = observations.compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            // boundingBox 归一化、原点左下 → 像素、原点左上的四点框
            let bb = obs.boundingBox
            let left = bb.origin.x * width
            let right = (bb.origin.x + bb.width) * width
            let topY = (1 - bb.origin.y - bb.height) * height
            let bottomY = (1 - bb.origin.y) * height
            return OcrLine(
                text: top.string,
                score: Double(top.confidence),
                box: [[left, topY], [right, topY], [right, bottomY], [left, bottomY]])
        }

        // 阅读顺序：自上而下、同行从左到右
        lines.sort { a, b in
            let ay = a.box.map { $0[1] }.min() ?? 0
            let by = b.box.map { $0[1] }.min() ?? 0
            if abs(ay - by) > 4 { return ay < by }
            return (a.box.map { $0[0] }.min() ?? 0) < (b.box.map { $0[0] }.min() ?? 0)
        }

        return OcrPage(pageNumber: options.pageNumber,
                       width: image.width, height: image.height,
                       lines: lines, markdown: nil)
    }
}
