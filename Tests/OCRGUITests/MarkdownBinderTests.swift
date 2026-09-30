import Testing
import Foundation
@testable import OCRGUICore

// MARK: - 退化检测

struct DegenerateTests {

    @Test("重复行视为退化")
    func repeatedLines() {
        let text = (0..<6).map { _ in "\\draw[thick,->] (0,0) -- (4,0);" }.joined(separator: "\n")
        #expect(OCRTextCleaner.isDegenerate(text))
    }

    @Test("连续相同行 3 次以上视为退化")
    func consecutiveRepeats() {
        let text = "正常一行\n相同\n相同\n相同\n结尾"
        #expect(OCRTextCleaner.isDegenerate(text))
    }

    @Test("正常文本不退化")
    func normalText() {
        let text = """
        设 $G$ 是一个群。由于 $(ab)(b^{-1}a^{-1})=e$，因此 $(ab)^{-1}=b^{-1}a^{-1}$。
        定义 1 循环群的概念如下。
        证明 由于 $ab=ba$，从而得证。$\\square$
        """
        #expect(!OCRTextCleaner.isDegenerate(text))
    }

    @Test("空/过短输出退化")
    func emptyIsDegenerate() {
        #expect(OCRTextCleaner.isDegenerate(""))
        #expect(OCRTextCleaner.isDegenerate("  \n  "))
        #expect(OCRTextCleaner.isDegenerate("很短"))
    }
}

// MARK: - Markdown 装订

struct MarkdownBinderTests {

    @Test("去掉 <md>/<doc> 包裹标签")
    func stripsWrapperTags() {
        let cleaned = OCRTextCleaner.clean("<md>\n第一章 群\n</md>\n正文 $x$。")
        #expect(!cleaned.contains("<md>"))
        #expect(!cleaned.contains("</doc>"))
        #expect(cleaned.contains("正文 $x$。"))
    }

    @Test("\\(..\\) → $..$，\\[..\\] → $$..$$")
    func convertsMathDelimiters() {
        let cleaned = OCRTextCleaner.clean(
            "由于 \\((ab)^{-1}=b^{-1}a^{-1}\\) 成立，且\n\\[(ab)(b^{-1}a^{-1})=e\\]\n所以得证。")
        #expect(cleaned.contains("$(ab)^{-1}=b^{-1}a^{-1}$"))
        #expect(cleaned.contains("$$"))
        #expect(cleaned.contains("(ab)(b^{-1}a^{-1})=e"))
        #expect(!cleaned.contains("\\\\("))
    }

    @Test("独立页码行被移除")
    func removesPageNumberLines() {
        let cleaned = OCRTextCleaner.clean("上一段内容\n\n42\n\n\u{00a0}\n下一段内容")
        #expect(!cleaned.contains("\n42\n"))
        #expect(cleaned.contains("上一段内容"))
        #expect(cleaned.contains("下一段内容"))
    }

    @Test("页首书眉（§标题+页码）被移除，正文中的行不受影响")
    func removesRunningHead() {
        let head = OCRTextCleaner.clean("§1.4 子群,Lagrange定理 43\n正文开始。")
        #expect(!head.contains("Lagrange定理 43"))
        #expect(head.contains("正文开始。"))

        // 非页首位置的同类行保留
        let keep = OCRTextCleaner.clean("引言。\n这里是 §1.4 子群,Lagrange定理 43 的引用。")
        #expect(keep.contains("Lagrange定理 43"))
    }

    @Test("标题升级为 Markdown 层级")
    func promotesHeadings() {
        let cleaned = OCRTextCleaner.clean("第一章 群\n§1.1 循环群\n习题1.1\n普通句子第一章 群不算标题")
        let lines = cleaned.split(separator: "\n").map(String.init)
        #expect(lines.contains("# 第一章 群"))
        #expect(lines.contains("## §1.1 循环群"))
        #expect(lines.contains("### 习题1.1"))
        #expect(lines.contains("普通句子第一章 群不算标题"))
    }

    @Test("多页记录装订为单一文档：页注释 + 兜底标注 + 汇总头")
    func bindsRecord() throws {
        var fallbackPage = OcrPage(pageNumber: 2, width: 1, height: 1, lines: [],
                                   markdown: "Task: Text Extraction. 结果")
        fallbackPage.usedFallback = true
        let record = HistoryRecord(
            fileName: "ch1.pdf", sourcePath: "/tmp/ch1.pdf", sourceKind: .pdf,
            engineID: "xiaomi-ocr-0", engineName: "Xiaomi-OCR-0",
            pages: [OcrPage(pageNumber: 1, width: 1, height: 1, lines: [], markdown: "\\(a\\) 第一页"),
                    fallbackPage,
                    OcrPage(pageNumber: 3, width: 1, height: 1, lines: [], markdown: "第二页正文")],
            editedText: nil)
        let bound = MarkdownBinder.bind(record: record)
        #expect(bound.contains("<!-- 第 1 页 -->"))
        #expect(bound.contains("<!-- 第 2 页 · 纯文本兜底"))
        #expect(bound.contains("$a$ 第一页"))
        #expect(bound.contains("第二页正文"))
        #expect(bound.contains("# ch1.pdf"))
    }
}
