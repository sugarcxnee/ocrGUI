import Foundation
import UniformTypeIdentifiers

// MARK: - 导出格式

public enum ExportFormat: String, CaseIterable, Sendable {
    case txt, md, json, csv, tex

    public var label: String {
        switch self {
        case .txt: return "纯文本 (.txt)"
        case .md: return "Markdown (.md)"
        case .json: return "JSON (.json)"
        case .csv: return "CSV 表格 (.csv)"
        case .tex: return "LaTeX 文档 (.tex)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .md: return "md"
        case .json: return "json"
        case .csv: return "csv"
        case .tex: return "tex"
        }
    }

    public var utType: UTType {
        switch self {
        case .txt: return .plainText
        case .md: return UTType(filenameExtension: "md") ?? .plainText
        case .json: return .json
        case .csv: return UTType(filenameExtension: "csv") ?? .plainText
        case .tex: return UTType(filenameExtension: "tex") ?? .plainText
        }
    }
}

// MARK: - 导出器

/// 导出为 txt / md / json / csv。JSON 与 CSV 字段沿用 webUI converters 约定，
/// 与其 outputs/ 产物兼容。
public enum Exporter {

    public static func content(record: HistoryRecord, format: ExportFormat) throws -> String {
        switch format {
        case .txt:
            return record.displayText
        case .md:
            // 多页未编辑的记录走"装订"：页眉页码清理、公式分隔符规范化、标题层级、页级注释
            if record.editedText == nil && record.pages.count > 1 {
                return MarkdownBinder.bind(record: record)
            }
            return record.displayText
        case .tex:
            return texString(record: record)
        case .json:
            return jsonString(record: record)
        case .csv:
            return csvString(record: record)
        }
    }

    // MARK: - LaTeX 文档（webUI tex 导出的等价物：ctexart 骨架，公式分隔符转回 \(..\) / \[.. \]）

    private static func texString(record: HistoryRecord) -> String {
        var body = record.displayText
        if let display = try? NSRegularExpression(pattern: #"\$\$(.+?)\$\$"#,
                                                  options: [.dotMatchesLineSeparators]) {
            body = display.stringByReplacingMatches(
                in: body, range: NSRange(body.startIndex..., in: body),
                withTemplate: "\\\\[$1\\\\]")  // $$..$$ → \[..\]
        }
        if let inline = try? NSRegularExpression(pattern: #"\$([^$\n]+?)\$"#) {
            body = inline.stringByReplacingMatches(
                in: body, range: NSRange(body.startIndex..., in: body),
                withTemplate: "\\\\($1\\\\)")  // $..$ → \(..\)
        }
        return """
        \\documentclass[UTF8]{ctexart}
        \\usepackage{amsmath,amssymb}
        \\begin{document}
        \(body)
        \\end{document}
        """
    }

    /// csv 带 UTF-8 BOM（Excel 直接打开不乱码），其余 UTF-8
    public static func data(record: HistoryRecord, format: ExportFormat) throws -> Data {
        let text = try content(record: record, format: format)
        switch format {
        case .csv:
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(text.utf8))
            return data
        default:
            return Data(text.utf8)
        }
    }

    public static func export(record: HistoryRecord, format: ExportFormat, to url: URL) throws {
        try data(record: record, format: format).write(to: url, options: .atomic)
    }

    /// 多记录合并（批量导出 all.txt 等）
    public static func batchContent(records: [HistoryRecord], format: ExportFormat) throws -> String {
        var parts: [String] = []
        for record in records {
            parts.append("==== \(record.fileName) ====\n" + (try content(record: record, format: format)))
        }
        return parts.joined(separator: "\n\n")
    }

    public static func batchExport(records: [HistoryRecord], fileName: String,
                                    format: ExportFormat, to url: URL) throws {
        let text = try batchContent(records: records, format: format)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    // MARK: - JSON（webUI lines_to_json 结构）

    private static func jsonString(record: HistoryRecord) -> String {
        struct PageJSON: Codable {
            let page: Int
            let width: Int
            let height: Int
            let lines: [LineJSON]
            let markdown: String?
        }
        struct LineJSON: Codable {
            let text: String
            let score: Double
            let box: [[Double]]
        }
        struct RecordJSON: Codable {
            let file_name: String
            let page_count: Int
            let pages: [PageJSON]
        }

        let object = RecordJSON(
            file_name: record.fileName,
            page_count: record.pages.count,
            pages: record.pages.map { page in
                PageJSON(page: page.pageNumber,
                         width: page.width,
                         height: page.height,
                         lines: page.lines.map { LineJSON(text: $0.text, score: $0.score, box: $0.box) },
                         markdown: page.markdown)
            })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        guard let data = try? encoder.encode(object) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - CSV（webUI 列头约定）

    private static func csvString(record: HistoryRecord) -> String {
        var rows: [String] = ["file_name,page,line_no,text,score,x1,y1,x2,y2,x3,y3,x4,y4"]
        for page in record.pages {
            if page.markdown != nil || page.lines.isEmpty {
                // VLM 整页结果：单行文本
                rows.append(csvRow(record.fileName, page.pageNumber, 1, page.mergedText, nil, nil))
                continue
            }
            for (index, line) in page.lines.enumerated() {
                let box = line.box.count == 4 ? line.box : nil
                rows.append(csvRow(record.fileName, page.pageNumber, index + 1, line.text, line.score, box))
            }
        }
        return rows.joined(separator: "\n")
    }

    private static func csvRow(_ file: String, _ page: Int, _ lineNo: Int,
                               _ text: String, _ score: Double?, _ box: [[Double]]?) -> String {
        var fields: [String] = [file, "\(page)", "\(lineNo)", escapeCSV(text)]
        fields.append(score.map(fmtScore) ?? "")
        if let box, box.count == 4 {
            for point in box {
                fields.append(fmt(point.count > 0 ? point[0] : 0))
                fields.append(fmt(point.count > 1 ? point[1] : 0))
            }
        } else {
            fields += Array(repeating: "", count: 8)
        }
        return fields.joined(separator: ",")
    }

    /// 1.0 → "1.0"，0.9800 → "0.98"（保留至少一位小数）
    private static func fmtScore(_ value: Double) -> String {
        var s = String(format: "%.4f", value)
        while s.hasSuffix("0") && !s.hasSuffix(".0") {
            s.removeLast()
        }
        return s
    }

    private static func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
