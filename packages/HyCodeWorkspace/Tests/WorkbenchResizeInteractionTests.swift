import CoreGraphics
import Testing

@testable import HyCodeWorkspace

struct WorkbenchResizeInteractionTests {
    private var visibility: WorkbenchVisibility {
        WorkbenchVisibility(project: true, information: true, openTabs: true, workspace: true)
    }
    private var frames: WorkbenchPaneFrames {
        WorkbenchPaneSizes().frames(width: 1360, height: 830, visibility: visibility)
    }
    private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    @Test func releaseWithoutMouseExitClearsLineAndBlocksDelayedEnter() {
        var state = WorkbenchResizeInteraction()
        state.pointer(at: center(frames.projectDivider), frames: frames, moved: true)
        #expect(state.indicator(in: frames, scale: 2)?.emphasized == true)
        state.begin(.project)
        state.enqueue(.project, value: 430)
        #expect(state.finish() == WorkbenchResizeRequest(axis: .project, value: 430))
        #expect(state.indicator(in: frames, scale: 2) == nil)
        state.pointer(at: center(frames.projectDivider), frames: frames, moved: false)
        #expect(state.indicator(in: frames, scale: 2) == nil)
        state.pointer(at: center(frames.projectDivider), frames: frames, moved: true)
        #expect(state.indicator(in: frames, scale: 2)?.emphasized == true)
        state.pointer(at: center(frames.editor), frames: frames, moved: true)
        state.pointer(at: center(frames.projectDivider), frames: frames, moved: false)
        #expect(state.indicator(in: frames, scale: 2) == nil)
    }

    @Test func windowLossClearsHoverAndKeyboardFocusWithoutAnyDrag() {
        for keyboard in [false, true] {
            var state = WorkbenchResizeInteraction()
            if keyboard {
                state.focus(.project)
            } else {
                state.pointer(at: center(frames.projectDivider), frames: frames, moved: true)
            }
            #expect(state.indicator(in: frames, scale: 2) != nil)
            state.reset()
            #expect(state.indicator(in: frames, scale: 2) == nil)
            state.pointer(at: center(frames.projectDivider), frames: frames, moved: false)
            #expect(state.indicator(in: frames, scale: 2) == nil)
        }
    }

    @Test func interruptionDropsQueuedResizeAndEveryIndicatorSource() {
        var state = WorkbenchResizeInteraction()
        state.focus(.information)
        state.begin(.bottom)
        state.enqueue(.bottom, value: 330)
        state.reset()
        #expect(state.dragging == nil)
        #expect(state.takePending() == nil)
        #expect(state.indicator(in: frames, scale: 2) == nil)
    }

    @Test func pointerBurstsCommitOnlyLatestValuePerDisplayAndOnceAtRelease() {
        var state = WorkbenchResizeInteraction()
        state.begin(.bottomSplit)
        for value in 220..<1000 { state.enqueue(.bottomSplit, value: Double(value)) }
        #expect(state.takePending() == WorkbenchResizeRequest(axis: .bottomSplit, value: 999))
        #expect(state.takePending() == nil)
        state.enqueue(.bottomSplit, value: 1001)
        #expect(state.finish() == WorkbenchResizeRequest(axis: .bottomSplit, value: 1001))
        #expect(state.finish() == nil)
        #expect(state.indicator(in: frames, scale: 2) == nil)
    }

    @Test func crossingOtherDividersWhileDraggingKeepsExactlyOneActiveLine() {
        var state = WorkbenchResizeInteraction()
        state.begin(.project)
        let active = state.indicator(in: frames, scale: 2)
        state.pointer(at: center(frames.informationDivider), frames: frames, moved: true)
        state.focus(.bottomSplit)
        state.enqueue(.information, value: 444)
        #expect(state.takePending() == nil)
        #expect(state.indicator(in: frames, scale: 2) == active)
        state.finish()
        #expect(state.indicator(in: frames, scale: 2) == nil)
    }

    @Test func removedOrTinyDividerNeverLeavesALineOutsideItsRoundedEndpoints() {
        var state = WorkbenchResizeInteraction()
        state.begin(.project)
        let hidden = WorkbenchPaneSizes().frames(
            width: 1360, height: 830, visibility: WorkbenchVisibility(project: false))
        #expect(state.indicator(in: hidden, scale: 2) == nil)
        let tiny = WorkbenchPaneSizes().frames(width: 16, height: 16, visibility: visibility)
        #expect(state.indicator(in: tiny, scale: 2) == nil)
        for axis in WorkbenchDivider.allCases {
            state.begin(axis)
            for scale in [1.0, 1.5, 2, 3] {
                let line = state.indicator(in: frames, scale: scale)!.frame
                #expect(frames[axis].contains(line))
                if axis.vertical {
                    #expect(line.minY == frames[axis].minY + 10)
                    #expect(line.maxY == frames[axis].maxY - 10)
                } else {
                    #expect(line.minX == frames[axis].minX + 10)
                    #expect(line.maxX == frames[axis].maxX - 10)
                }
            }
        }
    }

    @Test func movingTheBoundaryUsesOnlyTheLatestPresentedGeometry() {
        var state = WorkbenchResizeInteraction()
        state.begin(.project)
        let old = state.indicator(in: frames, scale: 2)!
        var sizes = WorkbenchPaneSizes()
        sizes.resize(.project, to: 500, width: 1360, height: 830, visibility: visibility)
        let moved = sizes.frames(width: 1360, height: 830, visibility: visibility)
        let new = state.indicator(in: moved, scale: 2)!
        #expect(old.frame != new.frame)
        #expect(moved.projectDivider.contains(new.frame))
        #expect(!frames.projectDivider.intersects(new.frame))
    }

    @Test func keyboardFocusIsNeutralAndPointerExitCannotLeaveBlue() {
        var state = WorkbenchResizeInteraction()
        state.focus(.information)
        #expect(state.indicator(in: frames, scale: 2)?.emphasized == false)
        state.pointer(at: center(frames.projectDivider), frames: frames, moved: true)
        #expect(state.indicator(in: frames, scale: 2)?.emphasized == true)
        state.clearHover()
        #expect(state.indicator(in: frames, scale: 2)?.emphasized == false)
        state.focus(nil)
        #expect(state.indicator(in: frames, scale: 2) == nil)
    }

    @Test func nonfiniteAndOutOfSessionEventsCannotResurrectPendingWork() {
        var state = WorkbenchResizeInteraction()
        state.enqueue(.project, value: 400)
        #expect(state.takePending() == nil)
        state.begin(.project)
        state.enqueue(.project, value: .nan)
        state.enqueue(.project, value: .infinity)
        #expect(state.finish() == nil)
        state.enqueue(.project, value: 500)
        #expect(state.takePending() == nil)
        #expect(state.indicator(in: frames, scale: .nan) == nil)
    }
}
