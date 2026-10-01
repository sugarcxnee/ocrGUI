import SwiftUI
import OCRGUICore

/// 右侧详情：左半原图预览（PDF 异步逐页渲染）、右半可编辑识别文本（大文档用 NSTextView 保持流畅）
struct RecordDetailView: View {
    @Environment(AppModel.self) private var model
    let record: HistoryRecord

    @State private var editedText: String = ""
    @State private var selectedPageNumber: Int = 1
    @State private var pdfPageImages: [Int: NSImage] = [:]
    @State private var renderingPage: Int?
    @State private var showBoxes = false
    @State private var pageLineCount: Int = 0
    @State private var pageMarkdown = false

    var body: some View {
        HSplitView {
            previewPane
                .frame(minWidth: 320, idealWidth: 520)
            editorPane
                .frame(minWidth: 300, idealWidth: 440, maxWidth: .infinity)
        }
        .onAppear {
            editedText = record.displayText
            selectedPageNumber = record.pages.first?.pageNumber ?? 1
            pageLineCount = record.pages.reduce(0) { $0 + $1.lines.count }
            pageMarkdown = record.pages.contains { $0.markdown != nil }
        }
        .onDisappear {
            persistEdit()
        }
    }

    // MARK: - 原图预览

    private var previewPane: some View {
        VStack(spacing: 0) {
            if record.pages.count > 1 {
                Picker("页", selection: $selectedPageNumber) {
                    ForEach(record.pages, id: \.pageNumber) { page in
                        Text("第 \(page.pageNumber) 页").tag(page.pageNumber)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)
            }
            if currentPage?.lines.isEmpty == false {
                Toggle("显示坐标框", isOn: $showBoxes)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            ScrollView([.vertical]) {
                pagePreview
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var pagePreview: some View {
        if let nsImage = imageForPage(selectedPageNumber) {
            ImageWithBoxes(nsImage: nsImage, page: currentPage, showBoxes: showBoxes)
                .frame(minHeight: 320)
        } else if renderingPage == selectedPageNumber {
            ProgressView("渲染第 \(selectedPageNumber) 页…")
                .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            ImageWithBoxes(nsImage: nil, page: currentPage, showBoxes: false)
        }
    }

    private var currentPage: OcrPage? {
        record.pages.first { $0.pageNumber == selectedPageNumber } ?? record.pages.first
    }

    /// 页图像：缓存 → 普通图片同步快路径 → PDF 异步渲染（不卡主线程）
    private func imageForPage(_ page: Int) -> NSImage? {
        if let cached = pdfPageImages[page] { return cached }
        if record.sourceKind == .pdf, let path = record.sourcePath {
            renderPDFPage(page, path: path)
            return nil
        }
        if let path = record.sourcePath, let image = NSImage(contentsOfFile: path) {
            pdfPageImages[page] = image
            return image
        }
        if let path = record.thumbnailPath {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    private func renderPDFPage(_ page: Int, path: String) {
        guard renderingPage != page else { return }
        renderingPage = page
        let url = URL(fileURLWithPath: path)
        let pageNumber = page
        Task.detached(priority: .userInitiated) {
            let loads = (try? PDFRenderer.render(url: url, dpi: 110)) ?? []
            let image = loads.first { $0.pageNumber == pageNumber }
                .map { NSImage(cgImage: $0.image, size: NSSize(width: $0.image.width, height: $0.image.height)) }
            await MainActor.run {
                pdfPageImages[pageNumber] = image
                if renderingPage == pageNumber { renderingPage = nil }
            }
        }
    }

    // MARK: - 文本编辑

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                exportMenu
                Button("保存修改") { persistEdit() }
                    .disabled(editedText == record.displayText)
                Button {
                    model.copyText(editedText)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
            .padding(8)

            Divider()

            FastTextView(text: $editedText)
        }
    }

    /// 详情页内导出（不依赖工具栏选中态）
    private var exportMenu: some View {
        Menu {
            ForEach(ExportFormat.allCases, id: \.self) { format in
                Button(format.label) {
                    export(format)
                }
            }
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
        .fixedSize()
    }

    private func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = (record.fileName as NSString).deletingPathExtension + format.fileExtension
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Exporter.export(record: record, format: format, to: url)
                model.statusMessage = "已导出：\(url.lastPathComponent)"
            } catch {
                model.errorMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private var metaText: String {
        var parts = ["\(record.engineName) · \(record.pages.count) 页"]
        if pageLineCount > 0 {
            parts.append("\(pageLineCount) 行")
        }
        if pageMarkdown {
            parts.append("Markdown")
        }
        if record.editedText != nil {
            parts.append("已编辑")
        }
        return parts.joined(separator: " · ")
    }

    private func persistEdit() {
        guard editedText != record.displayText else { return }
        model.saveEdit(record, newText: editedText)
    }
}

// MARK: - NSTextView 封装（大文本流畅编辑）

/// SwiftUI TextEditor 处理几十万字符会明显卡顿；NSTextView + TextStorage 可平滑处理。
struct FastTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.string = text
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// MARK: - 图片 + 坐标框 overlay

/// 等比显示原图；showBoxes 时把页面坐标框（像素、左上原点）映射到显示区域
struct ImageWithBoxes: View {
    let nsImage: NSImage?
    let page: OcrPage?
    let showBoxes: Bool

    var body: some View {
        GeometryReader { geo in
            if let nsImage, nsImage.size.width > 0, nsImage.size.height > 0 {
                let scale = min(geo.size.width / nsImage.size.width,
                                geo.size.height / nsImage.size.height)
                let drawn = CGSize(width: nsImage.size.width * scale,
                                   height: nsImage.size.height * scale)
                let offset = CGPoint(x: (geo.size.width - drawn.width) / 2,
                                     y: (geo.size.height - drawn.height) / 2)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: drawn.width, height: drawn.height)
                    if showBoxes, let page, page.width > 0, page.height > 0 {
                        ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                            let normalized = normalizedRect(of: line, in: page)
                            Rectangle()
                                .stroke(Color.orange, lineWidth: 1.5)
                                .background(Color.orange.opacity(0.08))
                                .frame(width: normalized.width * drawn.width,
                                       height: normalized.height * drawn.height)
                                .offset(x: offset.x + normalized.minX * drawn.width,
                                        y: offset.y + normalized.minY * drawn.height)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                VStack {
                    Image(systemName: "photo").font(.title)
                    Text("原文件不可用（剪贴板/已移动的文件仅保留缩略图）")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// 四点框（可能旋转）取外接矩形；坐标从左上原点像素归一化到 0-1（翻转 y 轴）
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
