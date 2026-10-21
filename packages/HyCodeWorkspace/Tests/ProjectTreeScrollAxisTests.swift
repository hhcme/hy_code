import Foundation
import Testing

@testable import HyCodeWorkspace

struct ProjectTreeScrollAxisTests {
    @Test func overflowMapsThumbPositionsToDocumentOffsets() {
        let axis = ProjectTreeScrollAxis(viewport: 25, extent: 100)
        #expect(axis.maximumOffset == 75)
        #expect(axis.knobProportion == 0.25)
        #expect(axis.normalized(30) == 0.4)
        #expect(axis.offset(for: 0.4) == 30)
        #expect(axis.normalized(75) == 1)
    }
    @Test func contentThatFitsHasNoScrollRangeEvenAfterShrinking() {
        let axis = ProjectTreeScrollAxis(viewport: 200, extent: 100)
        #expect(axis.maximumOffset == 0)
        #expect(axis.knobProportion == 1)
        #expect(axis.normalized(900) == 0)
        #expect(axis.offset(for: 1) == 0)
        #expect(axis.clamp(900) == 0)
    }
    @Test func invalidOrOvershootingPositionsStayFiniteAndWithinBounds() {
        let axis = ProjectTreeScrollAxis(viewport: 25, extent: 100)
        #expect(axis.offset(for: -1) == 0)
        #expect(axis.offset(for: 2) == 75)
        #expect(axis.normalized(-100) == 0)
        #expect(axis.normalized(1000) == 1)
        #expect(axis.clamp(.nan) == 0)
        let empty = ProjectTreeScrollAxis(viewport: .infinity, extent: .nan)
        #expect(empty.maximumOffset == 0)
        #expect(empty.knobProportion == 1)
        #expect(empty.offset(for: .nan) == 0)
    }
}
