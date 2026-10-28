import Testing

@testable import HyCodeWorkspace

struct WorkbenchDockingTests {
    @Test func defaultOpensFileListAndDedicatedCodexPanel() {
        let docking = WorkbenchDocking()
        #expect(docking.active == [.topLeading: .project, .topTrailing: .codex])
        #expect(
            docking.visibility
                == WorkbenchVisibility(project: true, information: true, openTabs: false, workspace: false))
        #expect(Set(docking.groups.values.flatMap { $0 }) == Set(WorkbenchTool.allCases))
    }

    @Test func clickingAnotherToolReplacesOnlyThatCornerAndClickingAgainClosesIt() {
        var docking = WorkbenchDocking()
        docking.hide(.codex)
        docking.toggle(.terminal)
        docking.toggle(.git)
        #expect(docking.isVisible(.project))
        #expect(docking.isVisible(.git))
        #expect(!docking.isVisible(.terminal))
        docking.toggle(.git)
        #expect(docking.active[.bottomLeading] == nil)
        docking.hide(.search)
        #expect(docking.isVisible(.project))
    }

    @Test func anOpenToolCarriesItsSelectionAcrossAllFourCorners() {
        for target in WorkbenchCorner.allCases {
            var docking = WorkbenchDocking()
            docking.hide(.codex)
            docking.move(.project, to: target, at: 0)
            #expect(docking.corner(of: .project) == target)
            #expect(docking.active[target] == .project)
            #expect(docking.active.values.filter { $0 == .project }.count == 1)
            if target != .topLeading { #expect(docking.active[.topLeading] == nil) }
        }
    }

    @Test func movingAnInactiveToolPreservesOpenPanelsAndSupportsAnEmptyGroup() {
        var docking = WorkbenchDocking()
        docking.hide(.codex)
        docking.move(.codex, to: .bottomTrailing, at: 999)
        docking.move(.information, to: .topLeading, at: 1)
        docking.move(.analysis, to: .topLeading, at: 2)
        #expect(docking.groups[.topTrailing] == [])
        #expect(docking.active == [.topLeading: .project])
        docking.move(.terminal, to: .topTrailing, at: 999)
        #expect(docking.groups[.topTrailing] == [.terminal])
        #expect(docking.active[.topTrailing] == nil)
    }

    @Test func insertionSlotsReorderInBothDirectionsWithoutChangingSelection() {
        var docking = WorkbenchDocking()
        docking.hide(.codex)
        docking.move(.project, to: .topLeading, at: 3)
        #expect(docking.groups[.topLeading] == [.search, .structure, .project])
        docking.move(.project, to: .topLeading, at: 0)
        #expect(docking.groups[.topLeading] == [.project, .search, .structure])
        docking.move(.project, to: .topLeading, at: 1)
        #expect(docking.groups[.topLeading] == [.project, .search, .structure])
        #expect(docking.active == [.topLeading: .project])
    }

    @Test func repeatedMovesNeverDuplicateOrLoseToolsAndKeepSelectionValid() {
        var docking = WorkbenchDocking()
        docking.hide(.codex)
        for (index, tool) in WorkbenchTool.allCases.enumerated() {
            for corner in WorkbenchCorner.allCases {
                docking.toggle(tool)
                docking.move(tool, to: corner, at: index % 4)
                let tools = docking.groups.values.flatMap { $0 }
                #expect(tools.count == WorkbenchTool.allCases.count)
                #expect(Set(tools) == Set(WorkbenchTool.allCases))
                for (position, selected) in docking.active {
                    #expect(docking.groups[position, default: []].contains(selected))
                }
            }
        }
    }
}
