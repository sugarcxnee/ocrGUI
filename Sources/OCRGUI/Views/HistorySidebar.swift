import SwiftUI
import OCRGUICore

/// 左栏：历史记录列表（可搜索、右键删除），重启后仍在；底部为处理队列
struct HistorySidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            recordList
            if !model.batch.jobs.isEmpty {
                Divider()
                QueuePanel()
            }
        }
    }

    private var recordList: some View {
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

// MARK: - 处理队列面板

struct QueuePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("队列 \(model.batch.doneCount)/\(model.batch.jobs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.batch.isRunning {
                    Button {
                        model.batch.cancel()
                    } label: {
                        Label("取消", systemImage: "stop.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.small)
                } else {
                    Button("清空") {
                        model.batch.clearFinished()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.batch.jobs) { job in
                        QueueRow(job: job)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 148)
        }
        .background(.bar)
    }
}

private struct QueueRow: View {
    let job: BatchJob

    private var icon: String {
        switch job.kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        case .other: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(job.fileName)
                .lineLimit(1)
                .font(.caption)
            Spacer()
            statusView
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusView: some View {
        switch job.status {
        case .pending:
            Text("等待").font(.caption2).foregroundStyle(.secondary)
        case .running(let page, let total):
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(total > 1 ? "第\(page)/\(total)页" : "识别中")
                    .font(.caption2).foregroundStyle(.blue)
            }
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .failed(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.red)
                .help(reason)
        case .cancelled:
            Text("已取消").font(.caption2).foregroundStyle(.orange)
        }
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord

    /// 缩略图缓存：避免列表滚动/刷新时反复解码 PNG
    private static let thumbCache = NSCache<NSString, NSImage>()

    private var thumbnail: NSImage? {
        guard let path = record.thumbnailPath else { return nil }
        if let cached = Self.thumbCache.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        Self.thumbCache.setObject(image, forKey: path as NSString)
        return image
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                }
            }
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
