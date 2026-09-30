import SwiftUI
import OCRGUICore

/// 右侧详情：左半原图预览、右半可编辑识别文本
struct RecordDetailView: View {
    @Environment(AppModel.self) private var model
    let record: HistoryRecord

    @State private var editedText: String = ""
    @State private var selectedPageNumber: Int = 1
    @State private var pdfPageImages: [Int: NSImage] = [:]
    @State private var showBoxes = false

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
                ImageWithBoxes(
                    nsImage: originalImage(forPage: selectedPageNumber),
                    page: currentPage,
                    showBoxes: showBoxes)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var currentPage: OcrPage? {
        record.pages.first { $0.pageNumber == selectedPageNumber } ?? record.pages.first
    }

    /// PDF 按页渲染预览；其他来源优先 sourcePath 原图，剪贴板退回缩略图
    private func originalImage(forPage page: Int) -> NSImage? {
        if record.sourceKind == .pdf, let path = record.sourcePath {
            if let cached = pdfPageImages[page] { return cached }
            guard let url = URL(string: path),
                  let loads = try? PDFRenderer.render(url: url, dpi: 110),
                  let load = loads.first(where: { $0.pageNumber == page }) else {
                return nil
            }
            let image = NSImage(cgImage: load.image,
                                size: NSSize(width: load.image.width, height: load.image.height))
            pdfPageImages[page] = image
            return image
        }
        if let path = record.sourcePath {
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        if let path = record.thumbnailPath {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    // MARK: - 文本编辑

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
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

            TextEditor(text: $editedText)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.visible)
        }
    }

    private var metaText: String {
        var parts = ["\(record.engineName) · \(record.pages.count) 页"]
        if record.pages.first(where: { !$0.lines.isEmpty }) != nil {
            let count = record.pages.reduce(0) { $0 + $1.lines.count }
            parts.append("\(count) 行")
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
