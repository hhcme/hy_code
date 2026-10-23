//! Revision-bound immutable markup projection, no file/network access. The host
//! enforces the WebKit resource/content policy for all HTML, including raw MD.
use crate::WorkspaceError;
use pulldown_cmark::{Event, Options, Parser, Tag, html};
use serde::Serialize;
use std::io::{self, Write};

pub const MAX_SOURCE: usize = 32 * 1024 * 1024;
const MAX_HTML: usize = 64 * 1024 * 1024;
#[derive(Serialize)]
pub struct SourceBlock {
    line: usize,
    id: String,
}
#[derive(Serialize)]
pub struct MarkupContent {
    html: String,
    blocks: Vec<SourceBlock>,
    markdown: bool,
}
fn failure(message: &str) -> WorkspaceError {
    WorkspaceError::new("markup_preview", message)
}
struct BoundedHTML(Vec<u8>);
impl Write for BoundedHTML {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > MAX_HTML.saturating_sub(self.0.len()) {
            return Err(io::Error::other("Preview HTML exceeds 64 MiB"));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
pub fn render(text: &str, markdown: bool) -> Result<MarkupContent, WorkspaceError> {
    render_cancellable(text, markdown, None)
}
pub fn render_cancellable(
    text: &str,
    markdown: bool,
    token: Option<&crate::HyCodeCancellation>,
) -> Result<MarkupContent, WorkspaceError> {
    crate::large_document::check(token)?;
    if text.len() > MAX_SOURCE {
        return Err(failure("预览文本超过 32 MiB，源码仍可编辑"));
    }
    if !markdown {
        return Ok(MarkupContent {
            html: text.to_owned(),
            blocks: vec![],
            markdown,
        });
    }
    // pulldown-cmark builds a tree in its constructor, before event limits.
    // Count dense syntax/lines BEFORE constructing it. Huge plain paragraphs
    // are cheap; millions of tiny list/emphasis nodes must not allocate GBs.
    let mut structural = 0usize;
    let mut lines = 0usize;
    for chunk in text.as_bytes().chunks(65_536) {
        crate::large_document::check(token)?;
        for byte in chunk {
            if matches!(byte, b'\n' | b'\r') {
                lines += 1;
            }
            if matches!(
                byte,
                b'\\'
                    | b'*'
                    | b'_'
                    | b'['
                    | b']'
                    | b'('
                    | b')'
                    | b'!'
                    | b'#'
                    | b'>'
                    | b'|'
                    | b'`'
                    | b'~'
                    | b'<'
                    | b'&'
                    | b'-'
                    | b'+'
            ) {
                structural += 1;
            }
        }
        if structural > 65_536 || lines > 100_000 {
            return Err(failure(
                "Markdown 结构密度超出整页预览预算；源码可继续分段编辑",
            ));
        }
    }
    let options = Options::ENABLE_TABLES
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_FOOTNOTES;
    let mut output = BoundedHTML(Vec::with_capacity(text.len().min(MAX_HTML)));
    let mut consumed = 0usize;
    let mut line = 0usize;
    let mut failed = None;
    let mut blocks = Vec::new();
    let mut nesting = 0usize;
    let mut last_line = None;
    let events = Parser::new_ext(text, options)
        .into_offset_iter()
        .enumerate()
        .scan((), |_, (count, (event, range))| {
            if count.is_multiple_of(256) && crate::large_document::check(token).is_err() {
                failed = Some("预览任务已取消");
                return None;
            }
            if count >= 100_000 {
                failed = Some("Markdown 结构超出预览预算");
                return None;
            }
            if let Event::Start(tag) = &event {
                nesting += 1;
                if nesting > 128 {
                    failed = Some("Markdown 嵌套超过 128 层");
                    return None;
                }
                if matches!(
                    tag,
                    Tag::Paragraph | Tag::Heading { .. } | Tag::CodeBlock(_) | Tag::Table(_)
                ) {
                    let end = range.start.max(consumed);
                    line += text[consumed..end]
                        .char_indices()
                        .filter(|(i, c)| {
                            matches!(c, '\n' | '\u{85}' | '\u{2028}' | '\u{2029}')
                                || (*c == '\r'
                                    && text.as_bytes().get(consumed + i + 1) != Some(&b'\n'))
                        })
                        .count();
                    consumed = end;
                    if last_line != Some(line) {
                        if blocks.len() >= 8192 {
                            failed = Some("Markdown 预览块超过 8192");
                            return None;
                        }
                        let id = format!("hycode-source-{line}");
                        let marker = Event::Html(
                            format!("<span id=\"{id}\" data-hycode-line=\"{line}\"></span>").into(),
                        );
                        blocks.push(SourceBlock { line, id });
                        last_line = Some(line);
                        return Some(vec![marker, event]);
                    }
                }
            } else if matches!(event, Event::End(_)) {
                nesting = nesting.saturating_sub(1);
            }
            Some(vec![event])
        })
        .flatten();
    html::write_html_io(&mut output, events)
        .map_err(|_| failure("Markdown 生成页面超过 64 MiB"))?;
    crate::large_document::check(token)?;
    if let Some(message) = failed {
        return Err(failure(message));
    }
    Ok(MarkupContent {
        html: String::from_utf8(output.0).map_err(|_| failure("预览编码失败"))?,
        blocks,
        markdown,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn gfm_preserves_unicode_tasks_tables_code_and_source_lines() {
        let value = render("# 标题😀\r\n\r\n- [x] 完成\r\n\r\n| A | B |\r\n| - | - |\r\n| 中 | 文 |\r\n\r\n```swift\r\nlet x = 1\r\n```\r\n", true).unwrap();
        assert!(value.html.contains("<h1>标题😀</h1>") && value.html.contains("type=\"checkbox\""));
        assert!(value.html.contains("<table>") && value.html.contains("language-swift"));
        assert_eq!(value.blocks.first().unwrap().line, 0);
        assert!(value.blocks.iter().any(|b| b.line == 8));
    }
    #[test]
    fn raw_html_is_only_projection_and_limits_are_explicit() {
        let html = "<style>p { color: red }</style><p>hello</p>";
        assert_eq!(render(html, false).unwrap().html, html);
        assert!(render(&"a".repeat(MAX_SOURCE + 1), true).is_err());
        let mut output = BoundedHTML(vec![0; MAX_HTML]);
        assert!(output.write_all(b"x").is_err());
        assert!(render(&"# a\n".repeat(8193), true).is_err());
    }
    #[test]
    fn dense_markdown_is_rejected_before_parser_and_plain_large_text_is_allowed() {
        assert!(render(&"- a\n".repeat(40_000), true).is_err());
        assert!(render(&"*a* ".repeat(40_000), true).is_err());
        assert!(render(&r"\.".repeat(70_000), true).is_err());
        let plain = "hello ".repeat(200_000);
        assert!(render(&plain, true).unwrap().html.contains("hello"));
        let token = crate::hycode_cancel_new();
        unsafe {
            crate::hycode_cancel(token);
        }
        assert_eq!(
            render_cancellable("# title", true, unsafe { token.as_ref() })
                .err()
                .unwrap()
                .code,
            "cancelled"
        );
        unsafe {
            crate::hycode_cancel_free(token);
        }
    }
    #[test]
    fn preview_revision_and_ffi_ownership_are_checked() {
        use crate::*;
        use std::{ptr, slice};
        let source = b"# before";
        unsafe {
            let mut doc = ptr::null_mut();
            let opened = hycode_text_open(source.as_ptr(), source.len(), &mut doc);
            hycode_buffer_free(opened.value);
            hycode_buffer_free(opened.error);
            let edit = hycode_text_replace(doc, 0, 2, 6, b"after".as_ptr(), 5);
            hycode_buffer_free(edit.value);
            hycode_buffer_free(edit.error);
            let stale = hycode_text_markup(doc, 0, true);
            assert!(!stale.error.data.is_null());
            hycode_buffer_free(stale.value);
            hycode_buffer_free(stale.error);
            let current = hycode_text_markup(doc, 1, true);
            assert!(current.error.data.is_null());
            let data = slice::from_raw_parts(current.value.data, current.value.len);
            assert!(String::from_utf8_lossy(data).contains("after"));
            hycode_buffer_free(current.value);
            hycode_buffer_free(current.error);
            hycode_text_free(doc);
            let invalid = hycode_text_markup(ptr::null(), 0, true);
            assert!(!invalid.error.data.is_null());
            hycode_buffer_free(invalid.value);
            hycode_buffer_free(invalid.error);
        }
    }
}
