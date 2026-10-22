import Foundation
import Testing

@testable import HyCodeWorkspace

struct DartDirectiveTests {
    private func target(_ offset: Int, _ text: String) -> NSRange? {
        DartDirectiveTarget.range(
            at: offset, in: text as NSString, lines: TextLineIndex(text, unicodeLineSeparators: false))
    }
    @Test func everyCharacterAndSeparatorSharesTheCompleteLibraryURI() {
        for text in [
            "import 'package:demo/a/file.dart';", "export \"../shared/file.dart\" show Value;",
            "part r'generated/file.g.dart';", "part of 'library.dart';", "import 'dart:async';",
            "// 😀\r\n  import 'package:项目/目录/类.dart';",
        ] {
            let source = text as NSString
            let open = text.contains("\"") ? source.range(of: "\"") : source.range(of: "'")
            let tail = source.substring(from: open.location + 1) as NSString
            let quote = text.contains("\"") ? "\"" : "'"
            let expected = NSRange(location: open.location + 1, length: tail.range(of: quote).location)
            let lines = TextLineIndex(text, unicodeLineSeparators: false)
            for offset in expected.location..<NSMaxRange(expected) {
                #expect(DartDirectiveTarget.range(at: offset, in: source, lines: lines) == expected)
            }
            #expect(target(open.location, text) == nil)
            #expect(target(NSMaxRange(expected), text) == nil)
        }
    }
    @Test func multilineAndConditionalURIsExcludeConditionComparisonStrings() {
        let text = """
            import /* comment */
              'base.dart'
              if (dart.library.io == 'true') /* outer /* inner */ done */ 'io.dart'
              if (dart.library.html) "web.dart";
            """
        let source = text as NSString
        for uri in ["base.dart", "io.dart", "web.dart"] {
            let expected = source.range(of: uri)
            for offset in expected.location..<NSMaxRange(expected) { #expect(target(offset, text) == expected) }
        }
        #expect(target(source.range(of: "true").location, text) == nil)
        #expect(target(source.range(of: "inner").location, text) == nil)
    }
    @Test func commentsCannotHideTheActualImportOrCreateAnEarlierFakeCandidate() {
        for text in [
            "/* note */ import 'dart:async';", "import /*\nimport 'example.dart';\n*/ 'dart:async';",
            "import'dart:async';", "import 'example.dart'; import 'dart:async';",
            "/*\nimport 'example.dart';\n*/\nimport 'dart:async';",
            "const note = '''\nimport 'example.dart';\n''';\nimport 'dart:async';",
        ] {
            let expected = (text as NSString).range(of: "dart:async")
            for offset in expected.location..<NSMaxRange(expected) { #expect(target(offset, text) == expected) }
            if text.contains("/*\n") || text.contains("'''\n") {
                #expect(target((text as NSString).range(of: "example.dart").location, text) == nil)
            }
        }
    }
    @Test func ordinaryStringsCommentsAndUnfinishedOrInterpolatedURIsAreNotDirectiveHits() {
        for text in [
            "const path = 'package:demo/a.dart';", "// import 'package:demo/a.dart';",
            "/* import 'package:demo/a.dart'; */", "imported 'package:demo/a.dart';",
            "import 'package:demo/a.dart", "import '''package:demo/a.dart''';",
            "import 'package:demo/$name/a.dart';", "import 'ok.dart';\nconst next = 'package:demo/a.dart';",
        ] {
            #expect(target((text as NSString).range(of: "a.dart").location + 1, text) == nil)
        }
    }
    @Test func lookupIsBoundedEvenForVeryLongLinesAndUnclosedDirectives() {
        let text = "import '" + String(repeating: "a", count: 20_000) + "/file.dart';"
        #expect(target(12, text) == nil)
        #expect(target(19_000, text) == nil)
        let multiline = "import\n" + String(repeating: "\n", count: 30) + "'file.dart';"
        #expect(target((multiline as NSString).range(of: "file.dart").location, multiline) == nil)
        #expect(target(-1, text) == nil && target((text as NSString).length, text) == nil)
    }
    @Test func unknownContextBeforeTheWindowCannotSwallowALaterRealDirective() {
        for note in ["author's note", "a ''' marker", "a \"\"\" marker"] {
            for directive in ["import 'dart:async';", "import\n  'dart:async';", "import /* note */\n  'dart:async';"] {
                let text = "/*\n" + String(repeating: "header\n", count: 16) + note + "\n*/\n" + directive
                let expected = (text as NSString).range(of: "dart:async")
                for offset in expected.location..<NSMaxRange(expected) { #expect(target(offset, text) == expected) }
            }
        }
    }
    @Test func packageMetadataKeepsLibrarySignatureAndDeclarationAsSeparateSections() {
        let content = DartHoverContent(
            contents: JSONValue([
                "kind": "markdown",
                "value":
                    "```dart\nlibrary package:demo/a.dart\n```\nDeclared in _package:demo/a.dart_.\n\n---\nLibrary docs.",
            ]))
        #expect(content.signature == "library package:demo/a.dart")
        #expect(content.declaration == "Declared in _package:demo/a.dart_.")
        #expect(content.documentation == "Library docs.")
    }
}
