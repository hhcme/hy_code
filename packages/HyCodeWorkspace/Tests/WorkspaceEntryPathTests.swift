import Foundation
import Testing

@testable import HyCodeWorkspace

struct WorkspaceEntryPathTests {
    @Test func rootItemRefersToTheRootAndCopiesADotInsteadOfAnEmptyPath() {
        let root = URL(fileURLWithPath: "/tmp/hycode-root", isDirectory: true)
        let entry = WorkspaceEntry(name: "hycode-root", relativePath: "", kind: .directory)
        #expect(entry.url(relativeTo: root) == root)
        #expect(entry.projectRelativePath == ".")
    }

    @Test func displayedAndCopiedPathsPreserveUnicodeSpacesAndLiteralPercentSigns() {
        let root = URL(fileURLWithPath: "/tmp/项目 100%", isDirectory: true)
        let relative = "目录 A/中文%20.swift"
        let entry = WorkspaceEntry(name: "中文%20.swift", relativePath: relative, kind: .file)
        #expect(entry.url(relativeTo: root).isFileURL)
        #expect(entry.url(relativeTo: root).path == "/tmp/项目 100%/目录 A/中文%20.swift")
        #expect(!entry.url(relativeTo: root).hasDirectoryPath)
        #expect(entry.projectRelativePath == relative)
        let directory = WorkspaceEntry(name: "目录 A", relativePath: "目录 A", kind: .directory)
        #expect(directory.url(relativeTo: root).hasDirectoryPath)
        #expect(directory.url(relativeTo: root).path == "/tmp/项目 100%/目录 A")
    }
}
