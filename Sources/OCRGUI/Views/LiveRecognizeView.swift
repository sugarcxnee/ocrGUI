import SwiftUI
import OCRGUICore

/// 批次进行中的实时预览：当前文件 + 正在识别的页 + 已完成页文本（逐页追加，自动滚动）；
/// 顶部提供本批次已完成文件的快捷入口（点击浏览，不打断识别）
struct LiveRecognizeView: View {
    let job: BatchJob
    let pages: [OcrPage]
    var completed: [HistoryRecord] = []
    var onSelect: (UUID) -> Void = { _ in }

    private var runningPage: (page: Int, total: Int)? {
        if case .running(let page, let total) = job.status {
            return (page, total)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !completed.isEmpty {
                completedChips
                Divider()
            }
            Divider()
            if pages.isEmpty {
                waitingView
            } else {
                pageListView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 本批次已完成文件（点击查看结果）
    private var completedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("已完成 \(completed.count)：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(completed.enumerated().reversed()), id: \.element.id) { index, record in
                    Button {
                        onSelect(record.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(record.fileName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.blue)
            Text(job.fileName).bold().lineLimit(1)
            if let current = runningPage {
                if current.total > 1 {
                    Text("第 \(current.page)/\(current.total) 页")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                }
            }
            Text("已完成 \(pages.count) 页")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Text("完成后自动保存；中途取消不丢已完成页（断点续跑）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
    }

    /// 第一页尚未完成时的等待视图（避免误显示"导入"空状态）
    private var waitingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            if let current = runningPage, current.total > 1 {
                Text("正在识别第 \(current.page)/\(current.total) 页…")
                    .monospacedDigit()
            } else {
                Text("正在识别 \(job.fileName)…")
            }
            Text("引擎可能需要预热（首次加载模型约 10–40 秒）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(pages, id: \.pageNumber) { page in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第 \(page.pageNumber) 页")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(page.mergedText)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(page.pageNumber)
                    }
                }
                .padding(14)
            }
            .onChange(of: pages.count) { _, _ in
                if let last = pages.last {
                    withAnimation {
                        proxy.scrollTo(last.pageNumber, anchor: .bottom)
                    }
                }
            }
        }
    }
}
