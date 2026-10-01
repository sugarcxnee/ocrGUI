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
    @State private var zoom: CGFloat = 1
    @State private var actualPixels = false
    @State private var pageInput = ""
    @State private var renderFailed = false
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
            pageInput = String(selectedPageNumber)
            pageLineCount = record.pages.reduce(0) { $0 + $1.lines.count }
            pageMarkdown = record.pages.contains { $0.markdown != nil }
        }
        .onChange(of: selectedPageNumber) { _, newValue in
            pageInput = String(newValue)
        }
        .onDisappear {
            persistEdit()
        }
    }

    // MARK: - 原图预览

    private var previewPane: some View {
        VStack(spacing: 0) {
            if record.pages.count > 8 {
                HStack(spacing: 10) {
                    Button {
                        stepPage(-1)
                    } label: { Image(systemName: "chevron.left") }
                    .disabled(selectedPageNumber <= minPageNumber)
                    Spacer()
                    TextField("页码", text: $pageInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.center)
                        .onSubmit { jumpToPageInput() }
                    Text("/ \(record.pages.count) 页")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        stepPage(1)
                    } label: { Image(systemName: "chevron.right") }
                    .disabled(selectedPageNumber >= maxPageNumber)
                }
                .controlSize(.regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else if record.pages.count > 1 {
                Picker("页", selection: $selectedPageNumber) {
                    ForEach(record.pages, id: \.pageNumber) { page in
                        Text("第 \(page.pageNumber) 页").tag(page.pageNumber)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)
            }
            HStack(spacing: 8) {
                if currentPage?.lines.isEmpty == false {
                    Toggle("坐标框", isOn: $showBoxes)
                        .toggleStyle(.checkbox)
                }
                Spacer()
                zoomControls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            Divider()

            pagePreview
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 缩放：−/＋/适应/1:1 实际像素（上限 32×）；触控板双指捏合亦可
    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                actualPixels = false
                zoom = max(0.2, zoom / 1.5)
            } label: { Image(systemName: "minus.magnifyingglass") }
            Button {
                actualPixels = false
                zoom = 1
            } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .help("适应窗口")
            Button {
                actualPixels = true   // 1 渲染像素 = 1 屏幕像素（200DPI 渲染下非常清晰）
            } label: { Text("1:1") }
                .help("实际像素")
            Button {
                actualPixels = false
                zoom = min(32, zoom * 1.5)
            } label: { Image(systemName: "plus.magnifyingglass") }
            Text(zoomLabel)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48)
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
    }

    private var zoomLabel: String {
        actualPixels ? "1:1" : String(format: "%.0f%%", zoom * 100)
    }

    // MARK: 翻页辅助

    private var minPageNumber: Int { record.pages.first?.pageNumber ?? 1 }
    private var maxPageNumber: Int { record.pages.last?.pageNumber ?? 1 }

    private func stepPage(_ delta: Int) {
        let numbers = record.pages.map(\.pageNumber)
        guard let index = numbers.firstIndex(of: selectedPageNumber) else { return }
        let target = index + delta
        guard numbers.indices.contains(target) else { return }
        selectedPageNumber = numbers[target]
    }

    private func jumpToPageInput() {
        guard let value = Int(pageInput.trimmingCharacters(in: .whitespaces)) else { return }
        let numbers = record.pages.map(\.pageNumber)
        let clamped = min(max(value, minPageNumber), maxPageNumber)
        // 页码可能有空洞（失败页）：取 ≥ 目标页的最近页
        selectedPageNumber = numbers.first { $0 >= clamped } ?? maxPageNumber
    }

    @ViewBuilder
    private var pagePreview: some View {
        if let nsImage = imageForPage(selectedPageNumber) {
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    // extent（≥可视区）由 PreviewLayout 决定：小图撑满居中，放大后可滚动
                    ImageWithBoxes(nsImage: nsImage, page: currentPage,
                                   showBoxes: showBoxes, zoom: zoom, viewport: geo.size,
                                   actualPixels: actualPixels)
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        actualPixels = false
                        zoom = min(32, max(0.2, value))
                    }
                    .onEnded { _ in }
            )
        } else if renderingPage == selectedPageNumber {
            ProgressView("渲染第 \(selectedPageNumber) 页…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if renderFailed || record.sourceKind == .clipboard || record.sourceKind == .screenshot {
            VStack(spacing: 8) {
                Image(systemName: "photo").font(.title)
                Text(record.thumbnailPath != nil ? "无原文件，仅缩略图" : "原文件不可用")
                    .font(.caption).foregroundStyle(.secondary)
                if let path = record.thumbnailPath {
                    ImageWithBoxes(nsImage: NSImage(contentsOfFile: path),
                                   page: currentPage, showBoxes: false, zoom: zoom,
                                   viewport: CGSize(width: 300, height: 300))
                        .frame(minHeight: 240)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentPage: OcrPage? {
        record.pages.first { $0.pageNumber == selectedPageNumber } ?? record.pages.first
    }

    /// 页图像：缓存 → 普通图片同步快路径 → PDF 单页异步渲染（高 DPI，供缩放核对）
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
        if let path = record.thumbnailPath, let image = NSImage(contentsOfFile: path) {
            pdfPageImages[page] = image
            return image
        }
        return nil
    }

    private func renderPDFPage(_ page: Int, path: String) {
        guard renderingPage != page else { return }
        renderingPage = page
        renderFailed = false
        let url = URL(fileURLWithPath: path)
        let pageNumber = page
        Task.detached(priority: .userInitiated) {
            let load = PDFRenderer.renderPage(url: url, page: pageNumber, dpi: 200)
            let image = load.map {
                NSImage(cgImage: $0.image, size: NSSize(width: $0.image.width, height: $0.image.height))
            }
            await MainActor.run {
                pdfPageImages[pageNumber] = image
                if image == nil { renderFailed = true }
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
