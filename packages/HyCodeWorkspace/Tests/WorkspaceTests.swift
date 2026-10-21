import Foundation
import Testing

@testable import HyCodeWorkspace

// No AppKit, NSApplication, GUI test host, clipboard or user-owned files.
@Suite(.serialized)
struct WorkspaceTests {
    @Test func nativeABIAndUnicodeDirectoryListing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hycode-swift-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("目录"), withIntermediateDirectories: false)
        try Data("hello".utf8).write(to: root.appendingPathComponent("中文😀.rs"))
        try Data().write(to: root.appendingPathComponent(".hidden"))
        let reader = NativeDirectoryReader(rootPath: root.path)
        #expect(NativeDirectoryReader.abiVersion == 1)
        let visible = try await reader.list(relativePath: "", includeHidden: false)
        #expect(visible.entries.count == 2)
        #expect(visible.entries.first?.kind == .directory)
        #expect(visible.entries.last?.name == "中文😀.rs")
        #expect(visible.entries.last?.size == 5)
        let all = try await reader.list(relativePath: "", includeHidden: true)
        #expect(all.entries.count == 3)
        do {
            _ = try await reader.list(relativePath: "../", includeHidden: false)
            Issue.record("Parent traversal should fail")
        } catch let error as WorkspaceFailure { #expect(error.code == "invalid_path") }
    }

    @Test func cancelledNativeReadNeverPublishesASnapshot() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeDirectoryReader(rootPath: FileManager.default.temporaryDirectory.path)
                .list(relativePath: "", includeHidden: false)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled read should not succeed")
        } catch is CancellationError {}
    }

    @Test func previewReplacementPinningAndClosingPreserveTabIdentity() throws {
        var state = BrowserTabs()
        func file(_ path: String) -> BrowserLocation {
            .file(WorkspaceEntry(name: path, relativePath: path, kind: .file))
        }
        state.open(file("main.swift"), preview: false)
        state.open(file("test.swift"), preview: true)
        state.open(file("other.swift"), preview: true)
        #expect(state.tabs.count == 2)
        let pinnedID = try #require(state.activeID)
        state.pin(pinnedID)
        state.open(file("readme.md"), preview: true)
        #expect(state.tabs.count == 3)
        state.open(file("other.swift"), preview: false)
        #expect(state.activeID == pinnedID)
        state.close(pinnedID)
        #expect(state.active?.location.path == "readme.md")
        #expect(state.tabs.filter(\.isPreview).count == 1)
    }

    @Test func directoriesNeverCreateOrReplaceDocumentTabs() throws {
        var state = BrowserTabs()
        state.open(.directory(""), preview: false)
        #expect(state.tabs.isEmpty)
        let file = WorkspaceEntry(name: "main.swift", relativePath: "main.swift", kind: .file)
        state.open(.file(file), preview: true)
        let id = state.activeID
        state.open(.directory("src"), preview: true)
        #expect(state.tabs.count == 1 && state.activeID == id)
        #expect(state.active?.location == .file(file))
    }

    @Test func simultaneousNativeReadsKeepTheirResultsSeparate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hycode-parallel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["one", "two", "three"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: folder.appendingPathComponent(name + ".txt"))
        }
        let reader = NativeDirectoryReader(rootPath: root.path)
        async let one = reader.list(relativePath: "one", includeHidden: false)
        async let two = reader.list(relativePath: "two", includeHidden: false)
        async let three = reader.list(relativePath: "three", includeHidden: false)
        let results = try await [one, two, three]
        #expect(results.map(\.relativePath) == ["one", "two", "three"])
        #expect(results.map { $0.entries.first?.name } == ["one.txt", "two.txt", "three.txt"])
    }

    @Test func branchingNavigationDiscardsForwardHistory() {
        var history = NavigationHistory()
        history.visit(.directory(""))
        history.visit(.directory("src"))
        history.visit(.directory("tests"))
        #expect(history.back() == .directory("src"))
        #expect(history.canGoForward)
        history.visit(.directory("docs"))
        #expect(!history.canGoForward)
        #expect(history.back() == .directory("src"))
        #expect(history.back() == .directory(""))
        #expect(history.back() == nil)
    }

    @Test func refreshedFileInformationPreservesPinnedTab() throws {
        var state = BrowserTabs()
        let original = WorkspaceEntry(name: "main.rs", relativePath: "src/main.rs", kind: .file, size: 2)
        state.open(.file(original), preview: false)
        let id = try #require(state.activeID)
        let updated = WorkspaceEntry(name: "main.rs", relativePath: "src/main.rs", kind: .file, size: 25)
        state.updateFileMetadata(from: [updated])
        #expect(state.activeID == id)
        #expect(state.active?.isPreview == false)
        #expect(state.active?.location == .file(updated))
    }

    @Test func parentNavigationFromFilesDoesNotSkipTheirContainingDirectory() {
        let nestedFile = WorkspaceEntry(name: "main.rs", relativePath: "src/main.rs", kind: .file)
        let rootFile = WorkspaceEntry(name: "README.md", relativePath: "README.md", kind: .file)
        #expect(BrowserLocation.file(nestedFile).parentDirectory == "src")
        #expect(BrowserLocation.file(rootFile).parentDirectory == "")
        #expect(BrowserLocation.directory("src").parentDirectory == "")
        #expect(BrowserLocation.directory("").parentDirectory == nil)
    }

    @Test func historyNavigationResolvesRefreshedFileMetadata() throws {
        let original = WorkspaceEntry(name: "main.rs", relativePath: "src/main.rs", kind: .file, size: 2)
        let updated = WorkspaceEntry(name: "main.rs", relativePath: "src/main.rs", kind: .file, size: 25)
        var history = NavigationHistory()
        var tabs = BrowserTabs()
        history.visit(.file(original))
        tabs.open(.file(original), preview: false)
        history.visit(.directory("docs"))
        tabs.updateFileMetadata(from: [updated])
        let previous = history.back()
        let destination = try #require(previous)
        tabs.open(destination.resolvingFile(in: [updated]), preview: true)
        #expect(tabs.active?.location == .file(updated))
        #expect(tabs.active?.isPreview == false)
    }
}
