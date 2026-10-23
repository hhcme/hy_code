import AppKit
import HyCodeWorkspace
import SwiftUI

extension WorkspaceEntry {
    var symbol: String {
        switch kind {
        case .directory: return "folder"
        case .symlink: return "link"
        case .other: return "questionmark.square.dashed"
        case .file:
            if ImagePreviewFormat.matches(name) { return "photo" }
            if VideoPreviewFormat.matches(name) { return "film" }
            return switch (name as NSString).pathExtension.lowercased() {
            case "swift", "rs", "c", "h", "cpp", "m", "mm", "js", "ts", "py", "go", "dart":
                "chevron.left.forwardslash.chevron.right"
            case "md", "txt", "log": "doc.text"
            case "json", "toml", "yaml", "yml", "plist": "slider.horizontal.3"
            default: "doc"
            }
        }
    }
    var symbolColor: NSColor {
        if isDirectory { return WorkbenchColors.nativeFolder }
        if kind == .symlink { return WorkbenchColors.nativeAccent }
        switch (name as NSString).pathExtension.lowercased() {
        case "swift", "rs", "c", "h", "cpp", "m", "mm", "js", "ts", "py", "go", "dart":
            return WorkbenchColors.nativeCode
        case "json", "toml", "yaml", "yml", "plist": return WorkbenchColors.nativeConfig
        case "md", "txt", "log": return WorkbenchColors.nativeDocument
        default: return WorkbenchColors.nativeSecondary
        }
    }
    var kindLabel: String {
        switch kind {
        case .directory: "目录"
        case .file: "文件"
        case .symlink: "符号链接"
        case .other: "其他"
        }
    }
    var sizeLabel: String {
        guard let size, size <= UInt64(Int64.max) else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    var modifiedLabel: String {
        guard let modifiedMs else { return "—" }
        return Date(timeIntervalSince1970: Double(modifiedMs) / 1_000).formatted(date: .numeric, time: .shortened)
    }
}

struct FileIcon: View {
    let entry: WorkspaceEntry
    var body: some View {
        Image(systemName: entry.symbol)
            .font(.system(size: 13))
            .foregroundStyle(Color(nsColor: entry.symbolColor))
            .frame(width: 18)
            .accessibilityHidden(true)
    }
}
