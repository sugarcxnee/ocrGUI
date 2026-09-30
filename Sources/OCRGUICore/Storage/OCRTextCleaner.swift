import Foundation

/// VLM 转写文本的退化检测与清洗（书籍/长文档场景）
public enum OCRTextCleaner {

    // MARK: - 退化检测

    /// 输出过短、空内容或重复行循环（常见于图形页）视为退化，
    /// 引擎配置了 fallback_prompt 时会自动重试。
    public static func isDegenerate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 30 { return true }

        let lines = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return true }

        // 同一行占比过高
        var counts: [String: Int] = [:]
        for line in lines { counts[line, default: 0] += 1 }
        if let maxCount = counts.values.max(), maxCount >= 4,
           Double(maxCount) / Double(lines.count) > 0.3 {
            return true
        }

        // 连续相同行 >= 3
        var run = 1
        for i in 1..<lines.count {
            if lines[i] == lines[i - 1] {
                run += 1
                if run >= 3 { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    // MARK: - 清洗（装订前）

    public static func clean(_ text: String) -> String {
        var result = text
        result = replaceAll(wrapperTag, in: result) { _ in "" }
        result = stripTableShell(result)
        result = replaceAll(inlineMath, in: result) { "$" + $0.trimmedForMath + "$" }
        result = replaceAll(displayMath, in: result) { "$$\n" + $0.trimmedForMath + "\n$$" }

        var lines = removePageFurniture(from: result.split(separator: "\n").map(String.init))
        lines = promoteHeadings(in: lines)

        // 去尾部孤立页码
        while let last = lines.last, isPageNumberLine(last) {
            lines.removeLast()
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 规则

    private static let wrapperTag = regex("^</?(md|doc|parsing|markdown)>$", anchors: true)
    private static let inlineMath = regex(#"\\\((.+?)\\\)"#, dotAll: true)
    private static let displayMath = regex(#"\\\[(.+?)\\\]"#, dotAll: true)
    /// multicolumn 单元格（模型爱把标题/整页内容塞进 LaTeX 表格壳）
    private static let multicolumn = regex(#"\\multicolumn\{2\}\{l\}\{(.*?)\}\s*(?:\\\\)?"#, dotAll: true)
    /// 表格壳格式噪音（判断"除单元格外无实质内容"用）
    private static let tableNoise = regex(
        #"\\(begin|end)\{tabular\}(\{[l |]*\})?|\\hline|\\quad|\\sffamily|\\textbf|&|\\\\|[{}\s]"#)
    /// 独立的表格壳标记行（含不闭合的壳）
    private static let tableShellLine = regex(
        #"^\\(begin\{table\}|end\{table\}|end\{tabular\}|begin\{tabular\}(\{[l |]*\}))?$"#, anchors: true)
    private static let pageNumberLine = regex(#"^\s*\d{1,3}\s*?$"#, anchors: true)
    /// 页首书眉：可选行首页码 + §节号 + 短标题 + **行尾页码**（必须有尾页码，
    /// 否则会误杀恰好在页首的真实节标题，如 "§1.1 循环群"）
    private static let runningHead = regex(
        #"^(\d{1,3}\s*[·•]?\s*)?§?\s*\d+\.\d+\s*[\p{Script=Han}（）()].{0,30}?\s+\d{1,3}$"#,
        anchors: true)

    private static func regex(_ pattern: String, dotAll: Bool = false, anchors: Bool = false) -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        if anchors { options.insert(.anchorsMatchLines) }
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func replaceAll(_ regex: NSRegularExpression, in input: String,
                                   template: (String) -> String) -> String {
        var mutable = input
        let matches = regex.matches(in: mutable, range: NSRange(mutable.startIndex..., in: mutable)).reversed()
        for match in matches {
            guard let range = Range(match.range, in: mutable) else { continue }
            let inner: String
            if match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: mutable) {
                inner = String(mutable[captureRange])
            } else {
                inner = ""
            }
            mutable.replaceSubrange(range, with: template(inner))
        }
        return mutable
    }

    /// 剥离模型输出的 LaTeX 表格壳：删除壳标记行；整行仅为 multicolumn 单元格时
    /// 把单元格文本释放为正文行；行内混有实质内容时只剥壳保留文本。
    private static func stripTableShell(_ text: String) -> String {
        var out: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let s = line.trimmingCharacters(in: .whitespaces)
            if tableShellLine.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
                continue
            }
            if s.contains("\\multicolumn") {
                let cells = captures(multicolumn, in: s)
                let residual = replaceAll(tableNoise, in: replaceAll(multicolumn, in: s) { _ in "" }) { _ in "" }
                    .replacingOccurrences(of: "l", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if residual.count < 5 {
                    var released = false
                    for cell in cells {
                        for piece in cell.components(separatedBy: " \\\\ ") {
                            let cleaned = piece.trimmingCharacters(in: .whitespaces)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
                                .trimmingCharacters(in: .whitespaces)
                            if !cleaned.isEmpty {
                                out.append(cleaned)
                                released = true
                            }
                        }
                    }
                    if released { continue }
                }
                out.append(replaceAll(multicolumn, in: line) { $0 })
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    private static func captures(_ regex: NSRegularExpression, in input: String) -> [String] {
        regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).compactMap {
            Range($0.range(at: 1), in: input).map { String(input[$0]) }
        }
    }

    private static func isPageNumberLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return pageNumberLine.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
    }

    /// 删除页首两行内的书眉与独立页码行；压缩首尾空行
    private static func removePageFurniture(from lines: [String]) -> [String] {
        var seenNonEmpty = 0
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if result.isEmpty { continue }  // 跳过页首空行
                result.append(line)
                continue
            }
            seenNonEmpty += 1
            let isHead = seenNonEmpty <= 2 && runningHead.firstMatch(
                in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
            if isPageNumberLine(trimmed) || isHead { continue }
            result.append(line)
        }
        // 去尾部空行
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeLast() }
        return result
    }

    private static func promoteHeadings(in lines: [String]) -> [String] {
        lines.map { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            if let level = headingLevel(for: s) {
                return String(repeating: "#", count: level) + " " + s
            }
            return line
        }
    }

    private static func headingLevel(for line: String) -> Int? {
        guard !line.hasPrefix("#") else { return nil }
        if line.range(of: "^第[一二三四五六七八九十]+章", options: .regularExpression) != nil, line.count < 30 {
            return 1
        }
        if line.range(of: "^§\\s*\\d+\\.\\d+", options: .regularExpression) != nil, line.count < 45 {
            return 2
        }
        if line.range(of: "^习题\\s*\\d+\\.\\d+", options: .regularExpression) != nil, line.count < 30 {
            return 3
        }
        return nil
    }
}

private extension String {
    var trimmedForMath: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
