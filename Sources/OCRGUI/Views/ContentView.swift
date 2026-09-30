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
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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
            Text("导入图片、粘贴剪贴板或拖放文件到此处开始识别")
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

            Divider()

            Button {
                if let record = model.selectedRecord {
                    model.copyText(record.displayText)
                }
            } label: {
                Label("复制文本", systemImage: "doc.on.doc")
            }
            .disabled(model.selectedRecord == nil)
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        let message = model.errorMessage.map { (text: $0, isError: true) }
            ?? model.statusMessage.map { (text: $0, isError: false) }
        if model.isProcessing || message != nil {
            HStack(spacing: 8) {
                if model.isProcessing {
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

