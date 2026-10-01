import SwiftUI
import OCRGUICore

/// 批次进行中的实时预览：当前文件名 + 已识别页的文本（逐页追加，自动滚动到底部）
struct LiveRecognizeView: View {
    let fileName: String
    let pages: [OcrPage]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                Text(fileName).bold()
                Text("已识别 \(pages.count) 页").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("完成后自动保存到历史记录")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(10)

            Divider()

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
                .onChange(of: pages.count) { _, count in
                    if let last = pages.last {
                        withAnimation {
                            proxy.scrollTo(last.pageNumber, anchor: .bottom)
                        }
                    }
                    _ = count
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
