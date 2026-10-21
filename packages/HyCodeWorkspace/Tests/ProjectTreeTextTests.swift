import Foundation
import Testing

@testable import HyCodeWorkspace

// CoreText only; no AppKit, NSApplication, GUI or user project files.
struct ProjectTreeTextTests {
    @Test func unicodeNamesKeepTheirPathIdentityAndActualGlyphWidths() async throws {
        let entries = [
            WorkspaceEntry(name: "iiii", relativePath: "src/narrow", kind: .file),
            WorkspaceEntry(name: "WWWW", relativePath: "src/wide", kind: .file),
            WorkspaceEntry(name: "中文😀_very_long_file_name.swift", relativePath: "src/unicode", kind: .file),
        ]
        let widths = try await ProjectTreeText.nameWidths(for: entries)
        #expect(Set(widths.keys) == Set(entries.map(\.relativePath)))
        #expect(widths.values.allSatisfy { $0.isFinite && $0 > 0 })
        #expect(try #require(widths["src/wide"]) > #require(widths["src/narrow"]))
        #expect(try #require(widths["src/unicode"]) > #require(widths["src/wide"]))
    }

    @Test func emptyAndWhitespaceInputsStayFinite() async throws {
        #expect(try await ProjectTreeText.nameWidths(for: []).isEmpty)
        let widths = try await ProjectTreeText.nameWidths(for: [
            WorkspaceEntry(name: "", relativePath: "empty", kind: .file),
            WorkspaceEntry(name: "   ", relativePath: "spaces", kind: .file),
        ])
        #expect(widths["empty"] == 0)
        #expect(try #require(widths["spaces"]).isFinite)
        #expect(try #require(widths["spaces"]) > 0)
    }

    @Test func cancelledPreparationNeverReturnsPartialWidths() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ProjectTreeText.nameWidths(for: [
                WorkspaceEntry(name: "cancelled", relativePath: "cancelled", kind: .file)
            ])
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled font preparation should not publish widths")
        } catch is CancellationError {}
    }

    @Test func independentBatchesDoNotShareResults() async throws {
        let first = [WorkspaceEntry(name: "one", relativePath: "first/one", kind: .file)]
        let second = [WorkspaceEntry(name: "two", relativePath: "second/two", kind: .file)]
        async let a = ProjectTreeText.nameWidths(for: first)
        async let b = ProjectTreeText.nameWidths(for: second)
        let (left, right) = try await (a, b)
        #expect(Set(left.keys) == ["first/one"])
        #expect(Set(right.keys) == ["second/two"])
    }
}
