import Foundation

/// 把多页识别记录装订为单一 Markdown 文档（书籍/长文档导出用）：
/// 逐页清洗（页眉页码/公式分隔符/标题层级）+ 页级来源注释 + 文档头。
public enum MarkdownBinder {

    public static func bind(record: HistoryRecord) -> String {
        let pages = record.pages
        let fallbackPages = Set(pages.filter { $0.usedFallback == true }.map(\.pageNumber))

        var parts: [String] = []
        for page in pages {
            var comment = "<!-- 第 \(page.pageNumber) 页"
            if fallbackPages.contains(page.pageNumber) {
                comment += " · 纯文本兜底（公式为纯文本形式）"
            }
            comment += " -->"
            let body = OCRTextCleaner.clean(page.mergedText)
            parts.append(comment + "\n\n" + body)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let header = """
        # \(record.fileName)\n
        > 引擎：\(record.engineName) · \(pages.count) 页 · 转写于 \(formatter.string(from: record.createdAt))\n
        > 兜底 \(fallbackPages.count) 页（图形页等无法 LaTeX 转写的页退化为纯文本）\n
        ---
        """
        return header + "\n\n" + parts.joined(separator: "\n\n---\n\n") + "\n"
    }
}
