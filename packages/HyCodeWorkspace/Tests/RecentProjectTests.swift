import Foundation
import Testing

@testable import HyCodeWorkspace

struct RecentProjectTests {
    @Test func revisitingMovesOneNormalizedRecordToTheFront() {
        var history = RecentProjects()
        history.remember(RecentProject(path: "/tmp/alpha/../one"))
        history.remember(RecentProject(path: "/tmp/two"))
        history.remember(RecentProject(path: "/tmp/one"))
        #expect(history.records.map(\.path) == ["/tmp/one", "/tmp/two"])
    }
    @Test func asynchronousBookmarkUpdateDoesNotReorderHistory() throws {
        var history = RecentProjects()
        history.remember(RecentProject(path: "/tmp/one"))
        history.remember(RecentProject(path: "/tmp/two"))
        history.updateBookmark(Data([1, 2]), path: "/tmp/one")
        let restored = try JSONDecoder().decode(RecentProjects.self, from: JSONEncoder().encode(history))
        #expect(restored.records.map(\.path) == ["/tmp/two", "/tmp/one"])
        #expect(restored.records.last?.bookmark == Data([1, 2]))
    }
    @Test func historyHasABoundedRecordCountAndStableBadges() {
        var history = RecentProjects()
        for index in 0..<40 { history.remember(RecentProject(path: "/tmp/project_\(index)")) }
        #expect(history.records.count == 30)
        #expect(RecentProject(path: "/tmp/flutter_package").initials == "FP")
        #expect(
            RecentProject(path: "/tmp/flutter_package").colorIndex
                == RecentProject(path: "/tmp/flutter_package").colorIndex)
    }
    @Test func startupRestoresTheLastOpenedProjectAndItsBookmark() throws {
        var history = RecentProjects()
        history.remember(RecentProject(path: "/tmp/one"))
        history.remember(RecentProject(path: "/tmp/two", bookmark: Data([4, 5])))
        let restored = try JSONDecoder().decode(RecentProjects.self, from: JSONEncoder().encode(history))
        #expect(restored.startupProject?.path == "/tmp/two")
        #expect(restored.startupProject?.bookmark == Data([4, 5]))
    }
    @Test func legacyHistoryWithoutAStartupFieldMigratesToItsFirstProject() throws {
        let data = Data(#"{"records":[{"path":"/tmp/two"},{"path":"/tmp/one"}]}"#.utf8)
        let restored = try JSONDecoder().decode(RecentProjects.self, from: data)
        #expect(restored.startupProject?.path == "/tmp/two")
    }
    @Test func explicitClosePersistsWithoutRemovingHistoryOrBeingUndoneByABookmark() throws {
        var history = RecentProjects()
        history.remember(RecentProject(path: "/tmp/one"))
        history.closeWorkspace()
        history.updateBookmark(Data([9]), path: "/tmp/one")
        let restored = try JSONDecoder().decode(RecentProjects.self, from: JSONEncoder().encode(history))
        #expect(restored.startupProject == nil)
        #expect(restored.records.count == 1)
        #expect(restored.records[0].bookmark == Data([9]))
        history.remember(RecentProject(path: "/tmp/two"))
        #expect(history.startupProject?.path == "/tmp/two")
    }
    @Test func unknownStartupRecordDoesNotSilentlyOpenAnotherProject() throws {
        let data = Data(#"{"records":[{"path":"/tmp/one"}],"startupPath":"/tmp/missing"}"#.utf8)
        let restored = try JSONDecoder().decode(RecentProjects.self, from: data)
        #expect(restored.startupProject == nil)
        #expect(restored.records.count == 1)
    }
}
