import Testing
import Foundation
@testable import OCRGUICore

// MARK: - OcrLine / OcrPage / HistoryRecord

@Test("OcrLine Codable 往返")
func ocrLineRoundtrip() throws {
    let line = OcrLine(text: "你好 world", score: 0.98, box: [[10, 20], [110, 20], [110, 50], [10, 50]])
    let data = try JSONEncoder().encode(line)
    let decoded = try JSONDecoder().decode(OcrLine.self, from: data)
    #expect(decoded == line)
}

@Test("OcrPage 合并文本：markdown 优先于行文本")
func ocrPageMergedTextPrefersMarkdown() {
    let page = OcrPage(pageNumber: 1, width: 100, height: 50,
                       lines: [OcrLine(text: "行1", score: 1, box: [])],
                       markdown: "# 标题")
    #expect(page.mergedText == "# 标题")

    let lineOnly = OcrPage(pageNumber: 1, width: 100, height: 50,
                           lines: [OcrLine(text: "行1", score: 1, box: []),
                                   OcrLine(text: "行2", score: 1, box: [])],
                           markdown: nil)
    #expect(lineOnly.mergedText == "行1\n行2")
}

@Test("OcrPage Codable 往返，markdown 为 nil 时省略")
func ocrPageRoundtripOmitsNilMarkdown() throws {
    let page = OcrPage(pageNumber: 2, width: 800, height: 600,
                       lines: [OcrLine(text: "abc", score: 0.5, box: [[0, 0], [1, 1], [2, 2], [3, 3]])],
                       markdown: nil)
    let data = try JSONEncoder().encode(page)
    let text = String(data: data, encoding: .utf8) ?? ""
    #expect(!text.contains("markdown"))
    #expect(try JSONDecoder().decode(OcrPage.self, from: data) == page)
}

@Test("HistoryRecord Codable 往返")
func historyRecordRoundtrip() throws {
    let record = HistoryRecord(
        fileName: "test.png",
        sourcePath: "/tmp/test.png",
        sourceKind: .image,
        engineID: "vision",
        engineName: "Vision",
        pages: [OcrPage(pageNumber: 1, width: 10, height: 10, lines: [], markdown: "hello")],
        editedText: nil)
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(HistoryRecord.self, from: data)
    #expect(decoded == record)
}

@Test("HistoryRecord 展示文本：用户编辑覆盖识别原文")
func historyRecordDisplayTextUsesEditOverride() {
    let page = OcrPage(pageNumber: 1, width: 10, height: 10, lines: [], markdown: "原始")
    let base = HistoryRecord(fileName: "a", sourcePath: nil, sourceKind: .image,
                             engineID: "e", engineName: "E", pages: [page], editedText: nil)
    #expect(base.displayText == "原始")

    let edited = HistoryRecord(fileName: "a", sourcePath: nil, sourceKind: .image,
                               engineID: "e", engineName: "E", pages: [page], editedText: "改过的")
    #expect(edited.displayText == "改过的")
}

@Test("多页展示文本用空行连接")
func historyRecordDisplayTextJoinsPages() {
    let p1 = OcrPage(pageNumber: 1, width: 1, height: 1, lines: [OcrLine(text: "一", score: 1, box: [])], markdown: nil)
    let p2 = OcrPage(pageNumber: 2, width: 1, height: 1, lines: [], markdown: "二")
    let record = HistoryRecord(fileName: "a.pdf", sourcePath: nil, sourceKind: .pdf,
                               engineID: "e", engineName: "E", pages: [p1, p2], editedText: nil)
    #expect(record.displayText == "一\n\n二")
}
