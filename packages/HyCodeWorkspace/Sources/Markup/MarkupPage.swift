import Foundation

public enum MarkupPage {
    public static let networkRuleListIdentifier = "HyCode.StaticPreview.Network.v2"
    // Omit resource-type restrictions so preconnect, DNS prefetch, ping and
    // future request categories are all covered. WebKit rejects alternation
    // (|), although ICU/JavaScript accept it, so use literal scheme prefixes.
    public static let networkRules =
        #"""
        [
          {"trigger":{"url-filter":"^http://","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
          {"trigger":{"url-filter":"^https://","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
          {"trigger":{"url-filter":"^ws://","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
          {"trigger":{"url-filter":"^wss://","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
          {"trigger":{"url-filter":"^ftp://","url-filter-is-case-sensitive":false},"action":{"type":"block"}}
        ]
        """#
    // Content JS is additionally disabled in WKWebpagePreferences. The app's
    // isolated-world scroll script does not run in the document content world.
    public static let policy =
        "default-src 'none'; script-src 'none'; style-src hycode-preview: 'unsafe-inline'; img-src hycode-preview:; font-src 'none'; media-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
    public static func document(_ content: MarkupPreviewContent, dark: Bool) -> String {
        let style =
            content.markdown
            ? """
            :root { color-scheme: \(dark ? "dark" : "light"); }
            body { font: 14px/1.65 -apple-system,BlinkMacSystemFont,sans-serif; margin: 0; padding: 24px 28px 48px;
              color: \(dark ? "#bcbec4" : "#27282e"); background: \(dark ? "#191a1c" : "#ffffff"); overflow-wrap: anywhere; }
            h1,h2,h3,h4,h5,h6 { line-height: 1.3; margin: 1.4em 0 .6em; }
            h1,h2 { border-bottom: 1px solid \(dark ? "#34363c" : "#dedfe3"); padding-bottom: .3em; }
            p,ul,ol,pre,table,blockquote { margin: .7em 0; }
            pre,code { font: 12px/1.6 ui-monospace,SFMono-Regular,monospace; }
            pre { background: \(dark ? "#242629" : "#f3f4f6"); padding: 14px; overflow: auto; border-radius: 6px; }
            :not(pre)>code { background: \(dark ? "#242629" : "#f3f4f6"); padding: 2px 4px; border-radius: 3px; }
            table { border-collapse: collapse; max-width: 100%; display: block; overflow: auto; }
            td,th { border: 1px solid \(dark ? "#45474e" : "#d1d3da"); padding: 5px 12px; }
            blockquote { border-left: 3px solid #6f737a; padding-left: 16px; color: #868a91; }
            img { max-width: 100%; height: auto; } a { color: #6b9bfa; } hr { border: 0; border-top: 1px solid #45474e; }
            * { scrollbar-color: #676a70 transparent; scrollbar-width: thin; }
            ::-webkit-scrollbar { width: 8px; height: 8px; } ::-webkit-scrollbar-track { background: transparent; }
            ::-webkit-scrollbar-thumb { background: #676a70; border: 2px solid transparent; background-clip: padding-box; border-radius: 6px; }
            """ : ""
        return
            "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>\(style)</style></head><body>\(content.html)</body></html>"
    }
}
