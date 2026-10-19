import XCTest
import HcCore
import HcLibrary

final class HcCoreTests: XCTestCase {
    private func fixtureURL() -> URL {
        Bundle.module.url(forResource: "sample", withExtension: "zip", subdirectory: "Fixtures")!
    }

    /// 核心链路验证：Rust 解析 ZIP 并返回条目，中文文件名保持 UTF-8。
    func testListEntriesWithUtf8Names() throws {
        let reader = try ZipReader.open(path: fixtureURL().path)

        XCTAssertEqual(reader.entryCount(), 3)
        let names = reader.entries().map(\.name)
        XCTAssertTrue(names.contains("hello.txt"))
        XCTAssertTrue(names.contains("中文名.txt"))
        XCTAssertTrue(names.contains("sub/nested.txt"))
    }

    func testOpenMissingFileThrowsOpenFailed() {
        XCTAssertThrowsError(try ZipReader.open(path: "/nonexistent/hc_missing.zip")) { error in
            guard case CoreError.OpenFailed = error else {
                return XCTFail("期望 CoreError.OpenFailed，实际 \(error)")
            }
        }
    }

    /// 入库流程验证：复制入库、来源保留、重启（重新 init）后记录仍在。
    @MainActor
    func testLibraryStoreImportsCopiesAndPersists() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("hc_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let store = LibraryStore(baseDirectory: base)
        let item = try store.importFile(at: fixtureURL())

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: item).path))
        XCTAssertEqual(item.sourcePath, fixtureURL().path)
        XCTAssertEqual(store.recents.first?.id, item.id)

        let reloaded = LibraryStore(baseDirectory: base)
        XCTAssertEqual(reloaded.recents.count, 1)
        XCTAssertEqual(reloaded.recents.first?.name, item.name)
    }
}
