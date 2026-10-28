import CoreGraphics
import Testing

@testable import HyCodeWorkspace

struct WorkbenchStyleTests {
    @Test func everyToolFitsTheTwoRailGroupsAtTheMinimumWindowHeight() {
        let height: CGFloat = 540 - WorkbenchStyleMetrics.headerHeight - WorkbenchStyleMetrics.statusHeight
        let side = WorkbenchStyleMetrics.toolSide
        let step = WorkbenchRailGeometry.step(height: height)
        for topCount in 0...WorkbenchTool.allCases.count {
            let bottomCount = WorkbenchTool.allCases.count - topCount
            let topStart = WorkbenchRailGeometry.start(count: topCount, top: true, height: height)
            let bottomStart = WorkbenchRailGeometry.start(count: bottomCount, top: false, height: height)
            let topEnd = topStart + CGFloat(max(0, topCount - 1)) * step + side
            let bottomEnd = bottomStart + CGFloat(max(0, bottomCount - 1)) * step + side
            if topCount > 0 { #expect(topStart >= 0 && topEnd <= height) }
            if bottomCount > 0 { #expect(bottomStart >= 0 && bottomEnd <= height) }
            if topCount > 0 && bottomCount > 0 { #expect(topEnd < bottomStart) }
        }
    }
    @Test func insertionUsesTheSameSlotsAsVisibleButtonsAndNeverEscapesTheRail() {
        let height: CGFloat = 461
        for top in [true, false] {
            for count in 0...WorkbenchTool.allCases.count {
                let start = WorkbenchRailGeometry.start(count: count, top: top, height: height)
                for index in 0..<count {
                    let buttonY = start + CGFloat(index) * WorkbenchRailGeometry.step(height: height)
                    #expect(
                        WorkbenchRailGeometry.insertionIndex(y: buttonY, count: count, top: top, height: height)
                            == index)
                }
                #expect(WorkbenchRailGeometry.insertionIndex(y: -100, count: count, top: top, height: height) == 0)
                #expect(
                    WorkbenchRailGeometry.insertionIndex(y: height + 100, count: count, top: top, height: height)
                        == count)
                for index in 0...count {
                    let y = WorkbenchRailGeometry.insertionY(index: index, count: count, top: top, height: height)
                    #expect(y >= 1 && y + 2 <= height - 1)
                }
            }
        }
    }
    @Test func ordinaryRailsKeepReferenceSpacingAndShortRailsCompactOnlyTheGaps() {
        #expect(WorkbenchRailGeometry.step(height: 821) == WorkbenchStyleMetrics.toolStep)
        let compact = WorkbenchRailGeometry.step(height: 461)
        #expect(compact < WorkbenchStyleMetrics.toolStep)
        #expect(compact >= WorkbenchStyleMetrics.toolSide + 2)
    }
    @Test func nativeButtonSizeIsPreservedWhileOriginsSnapInsideTheHeaderReserve() {
        for scale in [1.0, 1.5, 2, 3] {
            for side: CGFloat in [12, 14, 16] {
                var previous: CGRect?
                for index in 0..<3 {
                    let size = CGSize(width: side, height: side)
                    let rect = WorkbenchChromeGeometry.trafficLight(size: size, index: index, scale: scale)
                    #expect(rect.size == size)
                    #expect(rect.minY >= 0 && rect.maxY <= WorkbenchStyleMetrics.headerHeight)
                    #expect(rect.minX >= 0 && rect.maxX < WorkbenchStyleMetrics.trafficLightReserve)
                    #expect(abs(rect.midY - WorkbenchStyleMetrics.headerHeight / 2) <= 0.5 / scale)
                    #expect(abs(rect.minX * scale - (rect.minX * scale).rounded()) < 0.0001)
                    if let previous { #expect(previous.maxX < rect.minX) }
                    previous = rect
                }
            }
        }
    }
    @Test func shellChromeLeavesUsableEditorSpaceWithAllFourCorners() {
        let width = 860 - 2 * (WorkbenchStyleMetrics.stripeWidth + WorkbenchStyleMetrics.shellInset)
        let height = 540 - WorkbenchStyleMetrics.headerHeight - WorkbenchStyleMetrics.statusHeight
        let frames = WorkbenchPaneSizes().frames(
            width: width, height: height,
            visibility: WorkbenchVisibility(project: true, information: true, openTabs: true, workspace: true))
        #expect(frames.editor.width >= 360 && frames.editor.height >= 220)
        #expect(frames.openTabs.width >= 220 && frames.workspace.width >= 220)
        #expect(frames.project.maxX == frames.projectDivider.minX)
        #expect(frames.projectDivider.maxX == frames.editor.minX)
    }
}
