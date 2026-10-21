#[cfg(test)]
mod tests {
    use crate::{document::TextDocument, syntax_language::SyntaxLanguage};
    #[test]
    fn grammar_queries_load_and_color_all_supported_languages() {
        let samples = [
            (
                "main.dart",
                "class Example { final String name = 'text'; } // note",
            ),
            ("a.jsx", "const view = <div title='x'>{42}</div>; // note"),
            ("a.ts", "const message: string = 'hello'; // note"),
            (
                "a.tsx",
                "const view: JSX.Element = <div>{42}</div>; // note",
            ),
            ("a.html", "<!-- note --><div id='x'>hello</div>"),
            (
                "a.vue",
                "<template><div v-if=\"ok\">{{ name }}</div></template>",
            ),
            ("a.css", "/* note */ .box { color: red; width: 42px; }"),
            ("a.json", "{\"name\": \"value\", \"count\": 42}"),
            ("a.yaml", "# note\nname: value\ncount: 42\n"),
            ("a.toml", "# note\nname = \"value\"\ncount = 42\n"),
            ("a.c", "// note\nint main(void) { return 42; }"),
            (
                "a.cpp",
                "// note\nclass Example { public: int value = 42; };",
            ),
            ("a.rs", "// note\nfn main() { let value = \"hello\"; }"),
        ];
        for (path, text) in samples {
            SyntaxLanguage::for_path(path)
                .unwrap()
                .grammar()
                .unwrap_or_else(|e| panic!("{path}: {}", e.message));
            let mut doc = TextDocument::open(text.as_bytes()).unwrap();
            let result = doc
                .syntax(0, path, 0, text.encode_utf16().count())
                .unwrap_or_else(|e| panic!("{path}: {}", e.message));
            assert_eq!(result.status, "ready", "{path}");
            assert!(!result.spans.is_empty(), "{path}");
            assert!(
                result
                    .spans
                    .iter()
                    .all(|s| s.start + s.length <= text.encode_utf16().count())
            );
        }
    }
    #[test]
    fn edits_refresh_multiline_context_and_never_mutate_saved_text() {
        let text = "// 😀中\r\nlet value = \"text\";";
        let mut doc = TextDocument::open(text.as_bytes()).unwrap();
        let original = doc.bytes(0).unwrap();
        let result = doc
            .syntax(0, "a.rs", 0, text.encode_utf16().count())
            .unwrap();
        assert!(
            result
                .spans
                .iter()
                .any(|s| s.style.starts_with("comment") && s.start == 0)
        );
        assert_eq!(doc.bytes(0).unwrap(), original);
        doc.replace(0, 0, 0, "/*\n").unwrap();
        let units = doc.snapshot().text.encode_utf16().count();
        let incremental = doc.syntax(1, "a.rs", 0, units).unwrap();
        let mut fresh = TextDocument::open(&doc.bytes(1).unwrap()).unwrap();
        let fresh = fresh.syntax(0, "a.rs", 0, units).unwrap();
        assert_eq!(
            serde_json::to_value(incremental).unwrap(),
            serde_json::to_value(fresh).unwrap()
        );
        assert!(doc.syntax(0, "a.rs", 0, units).is_err());
        assert!(doc.syntax(1, "a.rs", 7, 8).is_err()); // Inside the emoji surrogate pair.
    }
    #[test]
    fn vue_and_html_inject_script_and_css_with_document_offsets() {
        for path in ["a.vue", "a.html"] {
            let text = "<script lang=\"ts\">const value: string = 'hello';</script><style>.box { color: red; }</style>";
            let mut doc = TextDocument::open(text.as_bytes()).unwrap();
            let result = doc.syntax(0, path, 0, text.len()).unwrap();
            let string = text.find("'hello'").unwrap();
            assert!(
                result
                    .spans
                    .iter()
                    .any(|s| s.start == string && s.style.starts_with("string")),
                "{path}: {:?}",
                result.spans
            );
            assert!(
                result
                    .spans
                    .iter()
                    .any(|s| &text[s.start..s.start + s.length] == "color"),
                "{path}"
            );
        }
    }
    #[test]
    fn limits_plain_text_and_scalar_ranges_are_explicit() {
        let mut doc = TextDocument::open("😀 let x=42;".as_bytes()).unwrap();
        assert!(doc.syntax(0, "a.rs", 1, 3).is_err());
        assert!(doc.syntax(0, "a.rs", 0, 65_537).is_err());
        assert_eq!(doc.syntax(0, "a.txt", 0, 2).unwrap().status, "plain");
        let mut large = TextDocument::open(&vec![b'x'; 1024 * 1024 + 1]).unwrap();
        assert_eq!(large.syntax(0, "a.rs", 0, 10).unwrap().status, "size_limit");
    }
    #[test]
    fn embedded_tags_and_merged_results_respect_viewport_and_budget() {
        let text = "<script>const x=1;</script>";
        let mut doc = TextDocument::open(text.as_bytes()).unwrap();
        for window in [0..7, 20..text.len(), 8..17] {
            let result = doc.syntax(0, "a.html", window.start, window.end).unwrap();
            assert!(
                result
                    .spans
                    .iter()
                    .all(|s| s.start >= window.start && s.start + s.length <= window.end)
            );
        }
        let block = "const value=42;".repeat(500);
        let text = format!("<script>{block}</script><script>{block}</script>");
        let mut doc = TextDocument::open(text.as_bytes()).unwrap();
        if let Ok(result) = doc.syntax(0, "a.html", 0, text.len()) {
            assert!(result.spans.len() <= 4096);
        }
    }
}
