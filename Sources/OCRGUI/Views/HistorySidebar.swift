import SwiftUI
import OCRGUICore

/// 左栏：历史记录列表（可搜索、右键删除），重启后仍在
struct HistorySidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding(
            get: { model.selectedRecordID },
            set: { model.selectedRecordID = $0 })) {
            ForEach(model.filteredRecords) { record in
                HistoryRow(record: record)
                    .tag(record.id)
                    .contextMenu {
                        Button("删除该记录", role: .destructive) {
                            model.deleteRecord(id: record.id)
                        }
                        Button("在 Finder 中显示原文件") {
                            if let path = record.sourcePath {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.filteredRecords.isEmpty {
                Text(model.searchText.isEmpty ? "暂无历史记录" : "无匹配结果")
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .top) {
            TextField("搜索文件名或文本", text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }))
                .textFieldStyle(.roundedBorder)
                .padding(8)
        }
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 36, height: 36)
                .background(Color(nsColor: .quaternaryLabelColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(record.fileName)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    kindIcon
                    Text(record.engineName)
                        .foregroundStyle(.secondary)
                    Text(record.createdAt.formatted(.dateTime.month().day().hour().minute()))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let path = record.thumbnailPath,
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
        }
    }

    private var kindIcon: some View {
        Image(systemName: iconFor(record.sourceKind))
            .foregroundStyle(.tertiary)
    }

    private func iconFor(_ kind: SourceKind) -> String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        case .other: return "doc"
        }
    }
}
