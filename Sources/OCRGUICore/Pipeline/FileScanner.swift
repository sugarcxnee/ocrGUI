import Foundation

/// 输入文件扫描：文件夹递归、类型判定
public enum FileScanner {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "bmp", "tif", "tiff", "webp", "heic"]

    /// 扩展名 → 输入类型（不支持的返回 nil）
    public static func kind(forExtension ext: String) -> SourceKind? {
        switch ext.lowercased() {
        case "pdf": return .pdf
        case let e where imageExtensions.contains(e): return .image
        default: return nil
        }
    }

    /// 递归扫描文件夹，返回支持的文件（图片 + PDF），按路径稳定排序；跳过隐藏文件
    public static func scan(folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            guard values?.isRegularFile == true else { continue }
            guard kind(forExtension: url.pathExtension) != nil else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
    }
}
