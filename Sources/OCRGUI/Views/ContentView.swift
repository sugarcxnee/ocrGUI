import SwiftUI
import UniformTypeIdentifiers
import OCRGUICore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isFileImporterPresented = false

    var body: some View {
        NavigationSplitView {
            HistorySidebar()
        } detail: {
            detailView
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        .frame(minWidth: 1000, minHeight: 640)
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $isFileImporterPresented,
                      allowedContentTypes: [.image, .pdf],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.importURLs(urls)
            }
        }
        .overlay(alignment: .bottom) { statusBar }
    }

    @ViewBuilder
    private var detailView: some View {
        if let record = model.selectedRecord {
            RecordDetailView(record: record)
                .id(record.id)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("导入图片/PDF、选择文件夹、粘贴剪贴板、截图，或拖放文件到此处")
                .foregroundStyle(.secondary)
            Text("首次使用建议先联网一次以完成 Vision 语言资源下载")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            model.importURLs(urls)
            return true
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("引擎", selection: Binding(
                get: { model.selectedEngineID },
                set: { model.selectedEngineID = $0 })) {
                ForEach(model.enabledEngines) { engine in
                    Text(engine.name).tag(engine.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 240)

            Button {
                isFileImporterPresented = true
            } label: {
                Label("导入图片", systemImage: "photo.badge.plus")
            }

            Button {
                chooseFolder()
            } label: {
                Label("导入文件夹", systemImage: "folder.badge.plus")
            }

            Button {
                model.importFromClipboard()
            } label: {
                Label("剪贴板", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button {
                model.importFromScreenshot()
            } label: {
                Label("截图", systemImage: "camera.viewfinder")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            if model.batch.isRunning {
                Button(role: .destructive) {
                    model.batch.cancel()
                } label: {
                    Label("取消", systemImage: "stop.circle")
                }
            }

            Divider()

            Button {
                if let record = model.selectedRecord {
                    model.copyText(record.displayText)
                }
            } label: {
                Label("复制文本", systemImage: "doc.on.doc")
            }
            .disabled(model.selectedRecord == nil)

            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(format.label) {
                        if let record = model.selectedRecord {
                            exportCurrentRecord(record, format: format)
                        }
                    }
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(model.selectedRecord == nil)
        }
    }

    /// 当前记录导出（P5 实现具体导出器前的占位行为由 Exporter 提供）
    private func exportCurrentRecord(_ record: HistoryRecord, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = (record.fileName as NSString)
            .deletingPathExtension + format.fileExtension
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

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择要批量识别的文件夹（递归扫描图片与 PDF）"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.importFolder(url)
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        let message = model.errorMessage.map { (text: $0, isError: true) }
            ?? model.statusMessage.map { (text: $0, isError: false) }
        if model.batch.isRunning || message != nil {
            HStack(spacing: 8) {
                if model.batch.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(message?.text ?? "")
                    .foregroundStyle(message?.isError == true ? Color.red : Color.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}
