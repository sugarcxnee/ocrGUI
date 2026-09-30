import Testing
import Foundation
@testable import OCRGUICore

// MARK: - Exporter 四格式

struct ExporterTests {

    private func linesRecord() -> HistoryRecord {
        HistoryRecord(
            fileName: "receipt.png",
            sourcePath: nil, sourceKind: .image,
            engineID: "paddle-classic", engineName: "Paddle",
            pages: [OcrPage(pageNumber: 1, width: 800, height: 500, lines: [
                OcrLine(text: "星辰咖啡馆", score: 1.0, box: [[249, 40], [420, 40], [420, 80], [249, 80]]),
                OcrLine(text: "订单编号: 20260917", score: 0.98, box: [[219, 110], [400, 110], [400, 140], [219, 140]]),
            ], markdown: nil)],
            editedText: nil)
    }

    private func markdownRecord() -> HistoryRecord {
        HistoryRecord(
            fileName: "paper.pdf",
            sourcePath: nil, sourceKind: .pdf,
            engineID: "paddle-vl", engineName: "VL",
            pages: [OcrPage(pageNumber: 1, width: 100, height: 100, lines: [], markdown: "# 标题"),
                    OcrPage(pageNumber: 2, width: 100, height: 100, lines: [], markdown: "| a | b |")],
            editedText: nil)
    }

    @Test("txt：行文本按行拼接，多页空行分隔；用户编辑优先")
    func txtFormat() throws {
        #expect(try Exporter.content(record: linesRecord(), format: .txt) == "星辰咖啡馆\n订单编号: 20260917")
        #expect(try Exporter.content(record: markdownRecord(), format: .txt) == "# 标题\n\n| a | b |")

        var edited = linesRecord()
        edited.editedText = "改过的文本"
        #expect(try Exporter.content(record: edited, format: .txt) == "改过的文本")
    }

    @Test("md：单页原样输出；多页走装订（含页注释与文档头）")
    func mdFormat() throws {
        let single = HistoryRecord(
            fileName: "one.png", sourcePath: nil, sourceKind: .image,
            engineID: "e", engineName: "E",
            pages: [OcrPage(pageNumber: 1, width: 1, height: 1, lines: [], markdown: "# 标题")],
            editedText: nil)
        #expect(try Exporter.content(record: single, format: .md) == "# 标题")

        let bound = try Exporter.content(record: markdownRecord(), format: .md)
        #expect(bound.contains("# paper.pdf"))
        #expect(bound.contains("<!-- 第 1 页 -->"))
        #expect(bound.contains("| a | b |"))
    }

    @Test("json：webUI 兼容结构（file_name/page_count/pages/lines/box 四点）")
    func jsonFormat() throws {
        let text = try Exporter.content(record: linesRecord(), format: .json)
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["file_name"] as? String == "receipt.png")
        #expect(json["page_count"] as? Int == 1)
        let pages = try #require(json["pages"] as? [[String: Any]])
        #expect(pages[0]["page"] as? Int == 1)
        let lines = try #require(pages[0]["lines"] as? [[String: Any]])
        #expect(lines.count == 2)
        #expect(lines[0]["text"] as? String == "星辰咖啡馆")
        #expect(lines[0]["score"] as? Double == 1.0)
        let box = try #require(lines[0]["box"] as? [[Double]])
        #expect(box.count == 4 && box[0] == [249, 40])
    }

    @Test("csv：表头 + 坐标列；markdown 页为一行；带 UTF-8 BOM")
    func csvFormat() throws {
        let csv = try Exporter.content(record: linesRecord(), format: .csv)
        let rows = csv.split(separator: "\n").map(String.init)
        #expect(rows[0] == "file_name,page,line_no,text,score,x1,y1,x2,y2,x3,y3,x4,y4")
        #expect(rows[1].hasPrefix("receipt.png,1,1,星辰咖啡馆,1.0,249,40,420,40,420,80,249,80"))
        #expect(rows.count == 3)

        let mdCSV = try Exporter.content(record: markdownRecord(), format: .csv)
        let mdRows = mdCSV.split(separator: "\n").map(String.init)
        #expect(mdRows.count == 3) // 表头 + 两页各一行

        // BOM
        let data = try Exporter.data(record: linesRecord(), format: .csv)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
    }

    @Test("csv 转义：逗号与引号")
    func csvEscaping() throws {
        var record = linesRecord()
        record.pages[0].lines[0].text = "包含,逗号 和 \"引号\""
        let csv = try Exporter.content(record: record, format: .csv)
        #expect(csv.contains("\"包含,逗号 和 \"\"引号\"\"\""))
    }

    @Test("批量合并导出")
    func batchContent() throws {
        let merged = try Exporter.batchContent(records: [linesRecord(), markdownRecord()], format: .txt)
        #expect(merged.contains("==== receipt.png ===="))
        #expect(merged.contains("==== paper.pdf ===="))
        #expect(merged.contains("订单编号: 20260917"))
    }

    @Test("写文件导出")
    func writesFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(record: linesRecord(), format: .txt, to: url)
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content == "星辰咖啡馆\n订单编号: 20260917")
    }
}
