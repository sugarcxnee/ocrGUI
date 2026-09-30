import SwiftUI
import OCRGUICore

/// 右侧详情：左半原图预览、右半可编辑识别文本
struct RecordDetailView: View {
    @Environment(AppModel.self) private var model
    let record: HistoryRecord

    @State private var editedText: String = ""
    @State private var selectedPageNumber: Int = 1
    @State private var pdfPageImages: [Int: NSImage] = [:]

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
            ScrollView([.vertical]) {
                previewImage
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var previewImage: some View {
        if let nsImage = originalImage(forPage: selectedPageNumber) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title)
                Text("原文件不可用（剪贴板/已移动的文件仅保留缩略图）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
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
