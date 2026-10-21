import Foundation
import Testing

@testable import HyCodeWorkspace

struct DartHoverTests {
    private func begin(_ state: inout DartHoverState) throws -> DartHoverState.Request {
        let value = state.begin()
        return try #require(value)
    }
    @Test func dartSignatureDeclarationAndDocumentationBecomeCompactSections() {
        let content = DartHoverContent(
            contents: JSONValue([
                "kind": "markdown",
                "value": """
                ```dart
                (new) EditorStartupGate()
                ```
                Declared in `EditorStartupGate` in _package:demo/widget/startup_gate.dart_.

                ---
                Creates a gate with **documentation** and `inline code`.
                """,
            ]))
        #expect(content.signature == "(new) EditorStartupGate()")
        #expect(content.declaration.hasPrefix("Declared in `EditorStartupGate`"))
        #expect(content.documentation == "Creates a gate with **documentation** and `inline code`.")
        #expect(!content.documentation.contains("---") && !content.signature.contains("```"))
    }
    @Test func plaintextLegacyAndIncompleteMarkdownRemainReadableAndBounded() {
        let legacy = DartHoverContent(
            contents: .array([
                JSONValue(["language": "dart", "value": "int count"]),
                .string("Type: `int`\nDeclared in _dart:core_.\n\n---\nA count."),
            ]))
        #expect(legacy.signature == "int count" && legacy.type == "`int`")
        #expect(legacy.documentation == "A count.")
        let malformed = DartHoverContent(contents: .string("```dart\nString broken(\n"))
        #expect(malformed.documentation == "String broken(")
        let large = DartHoverContent(contents: .string(String(repeating: "中", count: 20_000)))
        #expect(large.documentation.count == 8_000)
        #expect(DartHoverContent(contents: .null).isEmpty)
    }
    @Test func targetUsesWholeUnicodeIdentifiersAndRejectsWhitespaceAndNumericLiterals() {
        let source = "😀 fooBar.变量_2 $value 42\n" as NSString
        let name = source.range(of: "fooBar")
        for offset in name.location..<NSMaxRange(name) {
            #expect(DartHoverTarget.range(at: offset, in: source) == name)
        }
        #expect(
            DartHoverTarget.range(at: source.range(of: "变量_2").location + 1, in: source) == source.range(of: "变量_2"))
        #expect(
            DartHoverTarget.range(at: source.range(of: "$value").location + 2, in: source) == source.range(of: "$value")
        )
        for offset in [0, 1, 2, NSMaxRange(name), source.range(of: "42").location, source.length, -1] {
            #expect(DartHoverTarget.range(at: offset, in: source) == nil)
        }
        let astral = "𐐀name" as NSString
        #expect(DartHoverTarget.range(at: 1, in: astral) == NSRange(location: 0, length: astral.length))
        #expect(DartHoverTarget.range(at: 500, in: String(repeating: "a", count: 2_000) as NSString) == nil)
    }
    @Test func movingAcrossASymbolDoesNotResetItsDwellOrCreateMoreWorkers() throws {
        let text = "EditorStartupGate" as NSString
        var state = DartHoverState()
        let range = try #require(DartHoverTarget.range(at: 0, in: text))
        let moved = state.move(to: range)
        #expect(moved)
        let request = try begin(&state)
        for _ in 0..<20 {
            for offset in 0..<text.length {
                let changed = state.move(to: DartHoverTarget.range(at: offset, in: text))
                let extra = state.begin()
                #expect(!changed && extra == nil)
                #expect(state.isCurrent(request))
            }
        }
        let more = state.finish(request)
        #expect(!more)
    }
    @Test func cancelledAToBToAStillServicesTheLatestPointerAfterTheOldWorkerExits() throws {
        var state = DartHoverState()
        let a = NSRange(location: 1, length: 3)
        let b = NSRange(location: 8, length: 4)
        state.move(to: a)
        let old = try begin(&state)
        state.move(to: b)
        state.move(to: a)
        let extra = state.begin()
        #expect(extra == nil && !state.isCurrent(old))
        let more = state.finish(old)
        #expect(more)
        let current = try begin(&state)
        #expect(current.range == a && current.serial != old.serial && state.isCurrent(current))
        state.move(to: nil)
        let final = state.finish(current)
        let next = state.begin()
        #expect(!final && next == nil)
    }
    @Test func contextResetRejectsOldResultsWhileKeepingOnlyOneWorkerSlot() throws {
        var state = DartHoverState()
        let range = NSRange(location: 0, length: 3)
        state.reset(context: 10)
        state.move(to: range)
        let old = try begin(&state)
        state.reset(context: 11)
        state.move(to: range)
        state.store(.init(content: .init(contents: .string("old"))), for: old)
        let stale = state.entry(for: range)
        let extra = state.begin()
        #expect(stale == nil && extra == nil)
        let more = state.finish(old)
        #expect(more)
        let current = try begin(&state)
        #expect(current.context == 11 && state.isCurrent(current))
    }
    @Test func boundedLRUIncludesNegativeHoverAndDefinitionResults() throws {
        var state = DartHoverState()
        for index in 0..<17 {
            let range = NSRange(location: index * 4, length: 3)
            state.move(to: range)
            let request = try begin(&state)
            state.store(.init(content: .init(contents: .null), definition: DartHoverDefinition([])), for: request)
            state.finish(request)
        }
        let evicted = state.entry(for: NSRange(location: 0, length: 3))
        #expect(evicted == nil)
        let cached = state.entry(for: NSRange(location: 4, length: 3))
        let retained = try #require(cached)
        #expect(retained.content?.isEmpty == true && retained.definition?.targets.isEmpty == true)
        state.move(to: NSRange(location: 100, length: 3))
        let last = try begin(&state)
        state.store(retained, for: last)
        let kept = state.entry(for: NSRange(location: 4, length: 3))
        let removed = state.entry(for: NSRange(location: 8, length: 3))
        #expect(kept != nil && removed == nil)
    }
    @Test func oversizedDefinitionListsAreNotMistakenForCompleteNavigationCaches() {
        let position = LSPPosition(line: 0, character: 0)
        let target = LSPLocation(uri: "file:///fixture.dart", range: LSPRange(start: position, end: position))
        #expect(DartHoverDefinition([target]).complete)
        let value = DartHoverDefinition(Array(repeating: target, count: 33))
        #expect(value.targets.count == 32 && !value.complete)
    }
    @Test func modifierExpeditesTheSameSymbolWithoutLosingTheSingleWorkerSlot() throws {
        var state = DartHoverState()
        let range = NSRange(location: 20, length: 8)
        state.move(to: range)
        let waiting = try begin(&state)
        state.move(to: range, expedite: true)
        let extra = state.begin()
        #expect(extra == nil && !state.isCurrent(waiting))
        let reschedule = state.finish(waiting)
        #expect(reschedule)
        let expedited = try begin(&state)
        var entry = DartHoverEntry(content: .init(contents: .string("Documentation")))
        state.store(entry, for: expedited)
        entry.definition = DartHoverDefinition([])
        state.store(entry, for: expedited)
        let cached = state.entry(for: range)
        #expect(cached?.content?.documentation == "Documentation" && cached?.definition != nil)
    }
    @Test func cardsUseTheAnchorScreenIncludingNegativeCoordinatesAndStayInsideItsEdges() {
        let left = CGRect(x: -1_280, y: 0, width: 1_280, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        for anchor in [CGRect(x: -1_240, y: 700, width: 80, height: 18), CGRect(x: -90, y: 20, width: 80, height: 18)] {
            let screen = DartHoverPlacement.screen(for: anchor, screens: [left, right], fallback: right)
            let frame = DartHoverPlacement.frame(
                anchor: anchor, size: CGSize(width: 400, height: 180), screens: [left, right], fallback: right)
            #expect(screen == left && left.insetBy(dx: 8, dy: 8).contains(frame))
            if anchor.minY < 30 { #expect(frame.minY > anchor.maxY) }
        }
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 120)
        let frame = DartHoverPlacement.frame(
            anchor: .zero, size: CGSize(width: 500, height: 400), screens: [], fallback: tiny)
        #expect(tiny.insetBy(dx: 8, dy: 8).contains(frame))
    }
    @Test func aPointerCanCrossTheWhitespaceBridgeToEitherCardEdgeWithoutPreservingUnrelatedWhitespace() {
        let anchor = CGRect(x: 200, y: 500, width: 100, height: 18)
        let below = CGRect(x: 188, y: 393, width: 300, height: 100)
        for x in [200.0, 300.0, 480.0] {
            for y in 493...500 {
                #expect(DartHoverPlacement.isInBridge(CGPoint(x: x, y: Double(y)), anchor: anchor, panel: below))
            }
        }
        let above = CGRect(x: 188, y: 525, width: 300, height: 100)
        #expect(DartHoverPlacement.isInBridge(CGPoint(x: 470, y: 521), anchor: anchor, panel: above))
        #expect(!DartHoverPlacement.isInBridge(CGPoint(x: 150, y: 497), anchor: anchor, panel: below))
        #expect(!DartHoverPlacement.isInBridge(CGPoint(x: 210, y: 600), anchor: anchor, panel: below))
    }
}
