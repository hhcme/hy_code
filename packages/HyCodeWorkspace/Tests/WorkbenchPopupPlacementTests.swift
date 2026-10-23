import CoreGraphics
import Testing

@testable import HyCodeWorkspace

struct WorkbenchPopupPlacementTests {
    @Test func dropdownPrefersBelowAndAlignsToItsAnchor() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 92, y: 840, width: 150, height: 30)
        let result = WorkbenchPopupPlacement.dropdown(
            anchor: anchor,
            size: CGSize(width: 512, height: 400), screen: screen)
        #expect(result.minX == anchor.minX)
        #expect(result.maxY == anchor.minY - 4)
    }
    @Test func dropdownFlipsAboveWhenTheSpaceBelowIsInsufficient() {
        let screen = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let anchor = CGRect(x: -1200, y: 180, width: 150, height: 30)
        let result = WorkbenchPopupPlacement.dropdown(
            anchor: anchor,
            size: CGSize(width: 512, height: 400), screen: screen)
        #expect(result.minY == anchor.maxY + 4)
        #expect(screen.insetBy(dx: 6, dy: 6).contains(result))
    }
    @Test func submenuConnectsToTheVisibleRowAndFlipsAtTheRightEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 220, height: 100)
        let parent = CGRect(x: 100, y: 300, width: 250, height: 240)
        let row = CGRect(x: 106, y: 410, width: 238, height: 28)
        let result = WorkbenchPopupPlacement.submenu(parent: parent, row: row, size: size, screen: screen)
        #expect(result.minX == parent.maxX - 2)
        #expect(result.maxY == row.maxY + 6)
        let nearEdge = parent.offsetBy(dx: 600, dy: 0)
        let flipped = WorkbenchPopupPlacement.submenu(
            parent: nearEdge,
            row: row.offsetBy(dx: 600, dy: 0), size: size, screen: screen)
        #expect(flipped.maxX == nearEdge.minX + 2)
    }
    @Test func oversizedAndTinyPopupRequestsRemainInsideTheirDisplay() {
        for screen in [
            CGRect(x: -1600, y: 250, width: 1600, height: 900),
            CGRect(x: 0, y: 0, width: 20, height: 20),
        ] {
            for size in [CGSize(width: 2000, height: 3000), CGSize(width: 0, height: -1)] {
                let anchor = CGRect(x: screen.maxX - 2, y: screen.minY + 1, width: 1, height: 1)
                let dropdown = WorkbenchPopupPlacement.dropdown(anchor: anchor, size: size, screen: screen)
                let submenu = WorkbenchPopupPlacement.submenu(parent: anchor, row: anchor, size: size, screen: screen)
                for frame in [dropdown, submenu] {
                    #expect(frame.width >= 1 && frame.height >= 1)
                    #expect(screen.contains(frame))
                }
            }
        }
    }
}
