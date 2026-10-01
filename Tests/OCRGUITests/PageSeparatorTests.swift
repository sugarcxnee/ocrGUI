import Testing
import Foundation
@testable import OCRGUICore

// MARK: - 多页记录的分页标记（编辑视图显示页界，导出/复制剥离）

struct PageSeparatorTests {

    private func twoPageRecord(edited: String? = nil) -> HistoryRecord {
        HistoryRecord(fileName: "book.pdf", sourcePath: nil, sourceKind: .pdf,
                      engineID: "e", engineName: "E",
                      pages: [OcrPage(pageNumber: 1, width: 1, height: 1, lines: [], markdown: "第一页内容"),
                              OcrPage(pageNumber: 2, width: 1, height: 1, lines: [], markdown: "第二页内容")],
                      editedText: edited)
    }

    @Test("构建带页界标记的编辑文本；displayText 剥离标记")
    func buildAndStrip() {
        let record = twoPageRecord()
        let marked = record.markedTextForEditing
        #expect(marked.contains(HistoryRecord.pageSeparator(for: 1)))
        #expect(marked.contains(HistoryRecord.pageSeparator(for: 2)))
        #expect(marked.contains("第一页内容"))

        // 带标记的 editedText → displayText 无标记
        var edited = record
        edited.editedText = marked
        #expect(!edited.displayText.contains("─────"))
        #expect(edited.displayText.contains("第一页内容"))
        #expect(edited.displayText.contains("第二页内容"))
    }

    @Test("旧版无标记的 editedText 不受影响（向后兼容）")
    func legacyEditedTextUntouched() {
        var record = twoPageRecord(edited: "用户手改的整段文本")
        #expect(record.displayText == "用户手改的整段文本")
        // 无标记时 markedTextForEditing 原样返回
        #expect(record.markedTextForEditing == "用户手改的整段文本")
    }

    @Test("用户删除部分分隔行也能保存（剩余标记照常剥离）")
    func partialSeparators() {
        var record = twoPageRecord()
        record.editedText = "第一页内容\n───── 第 2 页 ─────\n改过的第二页"
        #expect(record.displayText == "第一页内容\n改过的第二页")
    }

    @Test("分隔行定位：查找页码在文本中的范围（编辑器滚动定位用）")
    func locatePageMarker() {
        let marked = twoPageRecord().markedTextForEditing
        let range = HistoryRecord.rangeOfPageMarker(1, in: marked)
        #expect(range != nil)
        let missing = HistoryRecord.rangeOfPageMarker(9, in: marked)
        #expect(missing == nil)
    }
}
