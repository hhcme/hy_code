import CoreGraphics
import Testing

@testable import HyCodeWorkspace

struct WorkbenchLayoutTests {
    private func visibility(_ bits: Int) -> WorkbenchVisibility {
        WorkbenchVisibility(
            project: bits & 1 != 0, information: bits & 2 != 0, openTabs: bits & 4 != 0, workspace: bits & 8 != 0)
    }
    private func rectangles(_ f: WorkbenchPaneFrames) -> [CGRect] {
        [
            f.project, f.editor, f.information, f.openTabs, f.workspace,
            f.projectDivider, f.informationDivider, f.bottomDivider, f.bottomSplitDivider,
        ]
    }

    @Test func allSixteenDockCombinationsFitWithoutOverlapAndKeepTheCenter() {
        let sizes = WorkbenchPaneSizes()
        for bits in 0..<16 {
            let v = visibility(bits)
            let f = sizes.frames(width: 780, height: 470, visibility: v)
            #expect(f.editor.width >= 360)
            #expect(f.editor.height >= 220)
            var visible = [f.editor]
            if v.project { visible.append(f.project) }
            if v.information { visible.append(f.information) }
            if v.openTabs { visible.append(f.openTabs) }
            if v.workspace { visible.append(f.workspace) }
            let viewport = CGRect(x: 0, y: 0, width: 780, height: 470)
            for (index, rect) in visible.enumerated() {
                #expect(viewport.contains(rect))
                for other in visible.dropFirst(index + 1) { #expect(!rect.intersects(other)) }
            }
        }
    }

    @Test func collapsingEveryDockLeavesExactlyTheFullContentRectangle() {
        let f = WorkbenchPaneSizes().frames(width: 1360, height: 830, visibility: visibility(0))
        #expect(f.editor == CGRect(x: 0, y: 0, width: 1360, height: 830))
        #expect(f.projectDivider.width == 0)
        #expect(f.informationDivider.width == 0)
        #expect(f.bottomDivider.height == 0)
        #expect(f.bottomSplitDivider.width == 0)
    }

    @Test func aSingleBottomDockFillsTheRowAndUpperDocksStopAboveIt() {
        let sizes = WorkbenchPaneSizes()
        for bits in [7, 11] {
            let f = sizes.frames(width: 1360, height: 830, visibility: visibility(bits))
            let bottom = bits == 7 ? f.openTabs : f.workspace
            #expect(bottom.minX == 0 && bottom.width == 1360)
            #expect(f.project.maxY == f.editor.maxY && f.information.maxY == f.editor.maxY)
            #expect(f.bottomDivider.minY == f.editor.maxY)
            #expect(f.bottomDivider.maxY == bottom.minY)
            #expect(f.bottomSplitDivider.width == 0)
        }
    }

    @Test func bothBottomDocksShareSnappedEdgesWithTheirDivider() {
        var sizes = WorkbenchPaneSizes()
        sizes.resize(.bottomSplit, to: 493.37, width: 1360, height: 830, visibility: visibility(15))
        let f = sizes.frames(width: 1360, height: 830, visibility: visibility(15))
        #expect(f.openTabs.maxX == f.bottomSplitDivider.minX)
        #expect(f.workspace.minX == f.bottomSplitDivider.maxX)
        #expect(f.workspace.maxX == 1360)
        #expect(f.openTabs.minY == f.workspace.minY)
        #expect(f.openTabs.height == f.workspace.height)
    }

    @Test func fittingOrHidingDoesNotOverwriteRememberedUserSizes() {
        var sizes = WorkbenchPaneSizes()
        sizes.resize(.project, to: 480, width: 1800, height: 900, visibility: visibility(15))
        sizes.resize(.information, to: 360, width: 1800, height: 900, visibility: visibility(15))
        sizes.resize(.bottom, to: 320, width: 1800, height: 900, visibility: visibility(15))
        sizes.resize(.bottomSplit, to: 700, width: 1800, height: 900, visibility: visibility(15))
        let remembered = sizes
        for bits in 0..<16 { _ = sizes.frames(width: 780, height: 470, visibility: visibility(bits)) }
        #expect(sizes == remembered)
        let restored = sizes.frames(width: 1800, height: 900, visibility: visibility(15))
        #expect(restored.project.width == 480)
        #expect(restored.information.width == 360)
        #expect(restored.openTabs.height == 320)
        #expect(restored.openTabs.width == 700)
    }

    @Test func extremeDraggingPreservesUsableCentralAndBottomPanes() {
        var sizes = WorkbenchPaneSizes()
        for axis in WorkbenchDivider.allCases {
            for value in [-1000.0, 100_000] {
                sizes.resize(axis, to: value, width: 780, height: 470, visibility: visibility(15))
                let f = sizes.frames(width: 780, height: 470, visibility: visibility(15))
                #expect(f.editor.width >= 360)
                #expect(f.editor.height >= 220)
                #expect(f.openTabs.width >= 220 && f.workspace.width >= 220)
                #expect(f.project.width >= 0 && f.information.width >= 0)
            }
        }
    }

    @Test func narrowingWindowFitsBottomMinimumWithoutForgettingTheSplitPreference() {
        for dragged in [220.0, 1574] {
            var sizes = WorkbenchPaneSizes()
            let v = visibility(15)
            sizes.resize(.bottomSplit, to: dragged, width: 1800, height: 900, visibility: v)
            let original = sizes.frames(width: 1800, height: 900, visibility: v)
            let narrow = sizes.frames(width: 780, height: 470, visibility: v)
            #expect(narrow.openTabs.width >= 220 && narrow.workspace.width >= 220)
            #expect(sizes.frames(width: 1800, height: 900, visibility: v) == original)
        }
    }

    @Test func resizingAfterWindowFittingDoesNotMoveTheOtherBoundary() {
        var sizes = WorkbenchPaneSizes()
        let v = visibility(15)
        let before = sizes.frames(width: 780, height: 470, visibility: v)
        sizes.resize(.project, to: before.project.width - 3, width: 780, height: 470, visibility: v)
        let after = sizes.frames(width: 780, height: 470, visibility: v)
        #expect(after.information == before.information)
        #expect(after.project.width == before.project.width - 3)
        #expect(after.editor.width == before.editor.width + 3)
    }

    @Test func animatedRegionsDoNotOverlapEvenWhenAllDockFlagsReverse() {
        let sizes = WorkbenchPaneSizes()
        for start in 0..<16 {
            for end in 0..<16 {
                let from = sizes.frames(width: 1360, height: 830, visibility: visibility(start))
                let to = sizes.frames(width: 1360, height: 830, visibility: visibility(end))
                for t in [0.0, 0.2, 0.5, 0.8, 1] {
                    let f = from.interpolated(to: to, progress: t, scale: 2)
                    let regions = [f.project, f.editor, f.information, f.openTabs, f.workspace].filter { !$0.isEmpty }
                    for (index, rect) in regions.enumerated() {
                        for other in regions.dropFirst(index + 1) { #expect(!rect.intersects(other)) }
                    }
                }
            }
        }
    }

    @Test func everyEdgeLandsOnBackingPixelsIncludingAnimationAndReversal() {
        let sizes = WorkbenchPaneSizes(projectWidth: 301.21, informationWidth: 279.83, bottomHeight: 219.12)
        for scale in [1.0, 1.5, 2] {
            for bits in 0..<16 {
                let from = sizes.frames(width: 1279.7, height: 799.8, visibility: visibility(bits), scale: scale)
                let to = sizes.frames(width: 1279.7, height: 799.8, visibility: visibility(15 - bits), scale: scale)
                for progress in [0.0, 0.17, 0.5, 0.83, 1] {
                    let midway = from.interpolated(to: to, progress: progress, scale: scale)
                    let reversed = midway.interpolated(to: from, progress: 0, scale: scale)
                    #expect(reversed == midway)
                    for rect in rectangles(midway) {
                        for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] {
                            #expect(abs(edge * scale - (edge * scale).rounded()) < 0.000_001)
                        }
                        #expect(rect.width >= 0 && rect.height >= 0)
                    }
                }
            }
        }
    }

    @Test func invalidOrTinyViewportNeverCreatesNegativeOrNonfiniteGeometry() {
        let sizes = WorkbenchPaneSizes(projectWidth: .infinity, informationWidth: .nan, bottomHeight: -.infinity)
        for dimension in [0.0, 1, 10, -1, .nan, .infinity] {
            for bits in 0..<16 {
                let f = sizes.frames(width: dimension, height: dimension, visibility: visibility(bits), scale: .nan)
                for rect in rectangles(f) {
                    #expect(rect.width.isFinite && rect.width >= 0)
                    #expect(rect.height.isFinite && rect.height >= 0)
                    #expect(rect.minX.isFinite && rect.minY.isFinite)
                }
            }
        }
    }
}
