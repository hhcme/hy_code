use crate::{
    WorkspaceError,
    syntax_language::{Grammar, SyntaxLanguage},
};
use serde::Serialize;
use std::{
    ops::{ControlFlow, Range},
    sync::Arc,
    time::{Duration, Instant},
};
use tree_sitter::{
    InputEdit, Node, ParseOptions, Parser, Point, QueryCursor, QueryCursorOptions,
    StreamingIterator, Tree,
};

pub const MAX_SYNTAX_BYTES: usize = 1024 * 1024;
const MAX_SPANS: usize = 4_096;
const MAX_WINDOW: usize = 65_536;

#[derive(Serialize, Debug)]
pub struct SyntaxSpan {
    pub start: usize,
    pub length: usize,
    pub style: String,
}
#[derive(Serialize)]
pub struct SyntaxSnapshot {
    pub language: &'static str,
    pub status: &'static str,
    pub start: usize,
    pub length: usize,
    pub spans: Vec<SyntaxSpan>,
}

/// A disposable parser cache attached to the formal document. Never owns another
/// text buffer. Edits update the old tree; parsing is deferred until the viewport
/// requests a versioned result. All work stays on the document's background actor.
pub struct SyntaxState {
    pub kind: SyntaxLanguage,
    grammar: Arc<Grammar>,
    parser: Parser,
    tree: Option<Tree>,
    dirty: bool,
}

fn failure(message: &str) -> WorkspaceError {
    WorkspaceError::new("syntax_unavailable", message)
}

impl SyntaxState {
    pub fn new(kind: SyntaxLanguage) -> Result<Self, WorkspaceError> {
        let grammar = kind.grammar()?;
        let mut parser = Parser::new();
        parser
            .set_language(&grammar.language)
            .map_err(|e| failure(&e.to_string()))?;
        Ok(Self {
            kind,
            grammar,
            parser,
            tree: None,
            dirty: true,
        })
    }
    pub fn edit(&mut self, text: &str, start: usize, end: usize, replacement: &str) {
        self.dirty = true;
        if let Some(tree) = &mut self.tree {
            let point = |byte: usize| {
                let prefix = &text.as_bytes()[..byte];
                Point {
                    row: prefix.iter().filter(|&&b| b == b'\n').count(),
                    column: prefix
                        .iter()
                        .rposition(|&b| b == b'\n')
                        .map_or(byte, |p| byte - p - 1),
                }
            };
            let start_position = point(start);
            let rows = replacement.bytes().filter(|&b| b == b'\n').count();
            let column = replacement
                .as_bytes()
                .iter()
                .rposition(|&b| b == b'\n')
                .map_or(start_position.column + replacement.len(), |p| {
                    replacement.len() - p - 1
                });
            tree.edit(&InputEdit {
                start_byte: start,
                old_end_byte: end,
                new_end_byte: start + replacement.len(),
                start_position,
                old_end_position: point(end),
                new_end_position: Point {
                    row: start_position.row + rows,
                    column,
                },
            });
        }
    }
    fn parse(&mut self, text: &str, deadline: Instant) -> Result<(), WorkspaceError> {
        if !self.dirty {
            return Ok(());
        }
        let mut progress = |_: &tree_sitter::ParseState| {
            if Instant::now() > deadline {
                ControlFlow::Break(())
            } else {
                ControlFlow::Continue(())
            }
        };
        let bytes = text.as_bytes();
        let mut input = |offset: usize, _: Point| &bytes[offset.min(bytes.len())..];
        let tree = self.parser.parse_with_options(
            &mut input,
            self.tree.as_ref(),
            Some(ParseOptions::new().progress_callback(&mut progress)),
        );
        match tree {
            Some(tree) => {
                self.tree = Some(tree);
                self.dirty = false;
                Ok(())
            }
            None => {
                self.parser.reset();
                Err(failure("语法解析超过后台预算"))
            }
        }
    }
    pub fn highlight(
        &mut self,
        text: &str,
        window: Range<usize>,
        deadline: Instant,
    ) -> Result<Vec<(usize, usize, String)>, WorkspaceError> {
        self.parse(text, deadline)?;
        let tree = self.tree.as_ref().ok_or_else(|| failure("语法树不可用"))?;
        let mut spans = captures(
            &self.grammar,
            tree.root_node(),
            text,
            window.clone(),
            deadline,
        )?;
        if matches!(self.kind, SyntaxLanguage::Vue | SyntaxLanguage::Html) {
            // Embedded scripts/styles are parsed from their complete block for context,
            // only when intersecting the viewport. No recursion or template execution.
            let mut cursor = tree.walk();
            let mut visited = 0;
            loop {
                let node = cursor.node();
                visited += 1;
                if visited > 40_000 || Instant::now() > deadline {
                    return Err(failure("嵌入语言超过后台预算"));
                }
                if node.start_byte() < window.end && node.end_byte() > window.start {
                    if let Some((body, language)) = injection(node, text) {
                        let intersection =
                            window.start.max(body.start_byte())..window.end.min(body.end_byte());
                        if intersection.start < intersection.end
                            && body.end_byte() - body.start_byte() <= 256 * 1024
                        {
                            let fragment = &text[body.byte_range()];
                            let mut embedded = Self::new(language)?;
                            let local = intersection.start - body.start_byte()
                                ..intersection.end - body.start_byte();
                            for (a, b, style) in embedded.highlight(fragment, local, deadline)? {
                                if spans.len() >= MAX_SPANS || Instant::now() > deadline {
                                    return Err(failure("合并高亮超过后台预算"));
                                }
                                spans.push((a + body.start_byte(), b + body.start_byte(), style));
                            }
                        }
                    } else if cursor.goto_first_child() {
                        continue;
                    }
                }
                loop {
                    if cursor.goto_next_sibling() {
                        break;
                    }
                    if !cursor.goto_parent() {
                        return Ok(spans);
                    }
                }
            }
        }
        Ok(spans)
    }
}

fn injection<'a>(node: Node<'a>, text: &str) -> Option<(Node<'a>, SyntaxLanguage)> {
    let language = match node.kind() {
        "script_element" => SyntaxLanguage::JavaScript,
        "style_element" => SyntaxLanguage::Css,
        "interpolation" => SyntaxLanguage::TypeScript,
        _ => return None,
    };
    let mut language = language;
    let mut body = None;
    let mut cursor = node.walk();
    for child in node.named_children(&mut cursor) {
        if child.kind() == "raw_text" {
            body = Some(child);
        }
        if child.kind() == "start_tag" {
            let mut attrs = child.walk();
            for attr in child
                .named_children(&mut attrs)
                .filter(|n| n.kind() == "attribute")
            {
                let mut parts = attr.walk();
                let parts: Vec<_> = attr.named_children(&mut parts).collect();
                if parts
                    .first()
                    .is_some_and(|n| &text[n.byte_range()] == "lang")
                {
                    let value = text[parts.last()?.byte_range()].trim_matches(['\'', '"']);
                    language = match value {
                        "ts" => SyntaxLanguage::TypeScript,
                        "tsx" => SyntaxLanguage::Tsx,
                        "js" | "jsx" => SyntaxLanguage::JavaScript,
                        "css" => SyntaxLanguage::Css,
                        _ => return None,
                    };
                }
            }
        }
    }
    body.map(|body| (body, language))
}

fn captures(
    grammar: &Grammar,
    root: Node<'_>,
    text: &str,
    window: Range<usize>,
    deadline: Instant,
) -> Result<Vec<(usize, usize, String)>, WorkspaceError> {
    let mut cursor = QueryCursor::new();
    cursor.set_byte_range(window.clone());
    cursor.set_match_limit(512);
    let mut progress = |_: &tree_sitter::QueryCursorState| {
        if Instant::now() > deadline {
            ControlFlow::Break(())
        } else {
            ControlFlow::Continue(())
        }
    };
    let mut matches = cursor.captures_with_options(
        &grammar.query,
        root,
        text.as_bytes(),
        QueryCursorOptions::new().progress_callback(&mut progress),
    );
    let mut spans = Vec::new();
    while let Some((result, index)) = matches.next() {
        if spans.len() >= MAX_SPANS || Instant::now() > deadline {
            return Err(failure("高亮结果超过后台预算"));
        }
        let capture = result.captures()[*index];
        let name = grammar.query.capture_names()[capture.index as usize];
        if name.starts_with('_') {
            continue;
        }
        let a = capture.node.start_byte().max(window.start);
        let b = capture.node.end_byte().min(window.end);
        if a < b {
            spans.push((a, b, name.to_owned()));
        }
    }
    drop(matches);
    if cursor.did_exceed_match_limit() || Instant::now() > deadline {
        return Err(failure("高亮查询超过后台预算"));
    }
    Ok(spans)
}

pub fn snapshot(
    state: &mut Option<SyntaxState>,
    text: &str,
    path: &str,
    start: usize,
    end: usize,
) -> Result<SyntaxSnapshot, WorkspaceError> {
    let kind = SyntaxLanguage::for_path(path);
    let mut result = SyntaxSnapshot {
        language: kind.map_or("Plain Text", SyntaxLanguage::name),
        status: "plain",
        start,
        length: end.saturating_sub(start),
        spans: Vec::new(),
    };
    let Some(kind) = kind else {
        return Ok(result);
    };
    if text.len() > MAX_SYNTAX_BYTES {
        *state = None;
        result.status = "size_limit";
        return Ok(result);
    }
    if end < start || end - start > MAX_WINDOW {
        return Err(failure("高亮范围无效或过大"));
    }
    if state.as_ref().is_none_or(|s| s.kind != kind) {
        *state = Some(SyntaxState::new(kind)?);
    }
    let deadline = Instant::now() + Duration::from_millis(100);
    let a = byte_at(text, start)?;
    let b = byte_at(text, end)?;
    let spans = state
        .as_mut()
        .ok_or_else(|| failure("语法状态不可用"))?
        .highlight(text, a..b, deadline)?;
    // Convert sorted byte boundaries once; never scan the prefix once per token.
    let mut boundaries: Vec<_> = spans.iter().flat_map(|(a, b, _)| [*a, *b]).collect();
    boundaries.sort_unstable();
    boundaries.dedup();
    let mut byte = a;
    let mut units = start;
    let mut offsets = std::collections::HashMap::new();
    for boundary in boundaries {
        units += text[byte..boundary].encode_utf16().count();
        byte = boundary;
        offsets.insert(boundary, units);
    }
    result.spans = spans
        .into_iter()
        .map(|(a, b, style)| SyntaxSpan {
            start: offsets[&a],
            length: offsets[&b] - offsets[&a],
            style,
        })
        .collect();
    // Parents first, then more specific captures; later patterns win equal spans.
    result
        .spans
        .sort_by_key(|span| std::cmp::Reverse(span.length));
    result.status = "ready";
    Ok(result)
}

fn byte_at(text: &str, position: usize) -> Result<usize, WorkspaceError> {
    let mut units = 0;
    for (byte, c) in text.char_indices() {
        if units == position {
            return Ok(byte);
        }
        units += c.len_utf16();
        if units > position {
            break;
        }
    }
    if units == position {
        Ok(text.len())
    } else {
        Err(failure("高亮范围切分 Unicode 或越界"))
    }
}
