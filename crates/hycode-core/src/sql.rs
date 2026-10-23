//! Bounded offline SQL projection. No connections, query execution or file I/O.
use crate::WorkspaceError;
use serde::Serialize;
use sqlparser::{
    ast::{Expr, Ident, ObjectName, Query, Select, Statement, TableFactor, Visit, Visitor},
    dialect::{
        AnsiDialect, BigQueryDialect, Dialect, DuckDbDialect, GenericDialect, MsSqlDialect,
        MySqlDialect, PostgreSqlDialect, SQLiteDialect, SnowflakeDialect,
    },
    keywords::Keyword,
    parser::Parser,
    tokenizer::{Location, Span, Token, TokenWithSpan, Tokenizer, Whitespace},
};
use std::{
    ops::ControlFlow,
    sync::{OnceLock, mpsc},
    thread,
};
const MAX_BYTES: usize = 256 * 1024;
#[derive(Serialize, Clone, Copy, Debug, PartialEq)]
pub struct Position {
    line: usize,
    character: usize,
}
#[derive(Serialize, Clone, Copy, Debug, PartialEq)]
pub struct Range {
    start: Position,
    end: Position,
}
#[derive(Serialize)]
pub struct Diagnostic {
    range: Range,
    severity: u8,
    message: String,
    source: &'static str,
}
#[derive(Serialize)]
pub struct Column {
    name: String,
    quoted: bool,
    detail: String,
    range: Range,
}
#[derive(Serialize)]
pub struct Table {
    name: String,
    quoted: bool,
    range: Range,
    columns: Vec<Column>,
}
#[derive(Serialize, Clone)]
pub struct Relation {
    name: String,
    quoted: bool,
}
#[derive(Serialize)]
pub struct Identifier {
    name: String,
    quoted: bool,
    role: &'static str,
    tables: Vec<Relation>,
    range: Range,
}
#[derive(Serialize)]
pub struct Analysis {
    diagnostics: Vec<Diagnostic>,
    tables: Vec<Table>,
    identifiers: Vec<Identifier>,
    formatted: Option<String>,
}
#[derive(Clone, Copy)]
struct Point {
    byte: usize,
    position: Position,
}
struct SourceMap {
    lines: Vec<Vec<Point>>,
}
impl SourceMap {
    fn new(text: &str) -> Self {
        let mut lines = vec![Vec::new()];
        let mut position = Position {
            line: 0,
            character: 0,
        };
        let mut cr = false;
        for (byte, c) in text.char_indices() {
            lines.last_mut().unwrap().push(Point { byte, position });
            if c == '\r' {
                position.line += 1;
                position.character = 0;
            } else if c == '\n' {
                if !cr {
                    position.line += 1;
                }
                position.character = 0;
            } else {
                position.character += c.len_utf16();
            }
            cr = c == '\r';
            if c == '\n' {
                lines.push(Vec::new());
            }
        }
        lines.last_mut().unwrap().push(Point {
            byte: text.len(),
            position,
        });
        Self { lines }
    }
    fn point(&self, location: Location) -> Point {
        self.lines
            .get(location.line.saturating_sub(1) as usize)
            .and_then(|line| {
                line.get(location.column.saturating_sub(1) as usize)
                    .or_else(|| line.last())
            })
            .copied()
            .unwrap_or_else(|| *self.lines.last().unwrap().last().unwrap())
    }
    fn range(&self, span: Span) -> Range {
        Range {
            start: self.point(span.start).position,
            end: self.point(span.end).position,
        }
    }
    fn raw<'a>(&self, span: Span, text: &'a str) -> &'a str {
        text.get(self.point(span.start).byte..self.point(span.end).byte)
            .unwrap_or("")
    }
    fn error(&self, error: String) -> Diagnostic {
        let (line, column) = error
            .rsplit_once(" at Line: ")
            .and_then(|(_, rest)| rest.split_once(", Column: "))
            .and_then(|(l, c)| {
                Some((
                    l.parse::<u64>().ok()?,
                    c.split_whitespace().next()?.parse::<u64>().ok()?,
                ))
            })
            .unwrap_or((1, 1));
        let point = self.point(Location { line, column });
        let end = self.point(Location {
            line,
            column: column.saturating_add(1),
        });
        Diagnostic {
            range: Range {
                start: point.position,
                end: end.position,
            },
            severity: 1,
            message: error.chars().take(2000).collect(),
            source: "SQL (offline)",
        }
    }
}
fn dialect(id: u32) -> Result<Box<dyn Dialect>, WorkspaceError> {
    Ok(match id {
        0 => Box::new(GenericDialect),
        1 => Box::new(PostgreSqlDialect {}),
        2 => Box::new(MySqlDialect {}),
        3 => Box::new(SQLiteDialect {}),
        4 => Box::new(MsSqlDialect {}),
        5 => Box::new(DuckDbDialect {}),
        6 => Box::new(BigQueryDialect {}),
        7 => Box::new(SnowflakeDialect {}),
        8 => Box::new(AnsiDialect {}),
        _ => return Err(WorkspaceError::new("sql_dialect", "未知 SQL 方言")),
    })
}
fn table_name(name: &ObjectName) -> String {
    name.0
        .iter()
        .map(|part| part.as_ident().map(|i| i.value.clone()).unwrap_or_default())
        .collect::<Vec<_>>()
        .join(".")
}
type Job = (
    String,
    u32,
    bool,
    mpsc::SyncSender<Result<Analysis, WorkspaceError>>,
);
pub fn analyze(text: &str, id: u32, formatting: bool) -> Result<Analysis, WorkspaceError> {
    if text.len() > MAX_BYTES || text.contains('\0') {
        return Err(WorkspaceError::new(
            "sql_budget",
            "SQL 离线检查限 256 KiB 且不含空字符",
        ));
    }
    // One lazy bounded worker gives parser/visitor/AST destruction a known
    // stack independent of the caller's small Swift cooperative worker stack.
    static WORKER: OnceLock<Result<mpsc::SyncSender<Job>, String>> = OnceLock::new();
    let worker = WORKER
        .get_or_init(|| {
            let (tx, rx) = mpsc::sync_channel::<Job>(1);
            thread::Builder::new()
                .name("HyCodeSQL".into())
                .stack_size(16 * 1024 * 1024)
                .spawn(move || {
                    while let Ok((text, id, format, reply)) = rx.recv() {
                        let result = std::panic::catch_unwind(|| analyze_inner(&text, id, format))
                            .unwrap_or_else(|_| {
                                Err(WorkspaceError::new("sql_internal", "SQL 解析内部错误"))
                            });
                        let _ = reply.send(result);
                    }
                })
                .map(|_| tx)
                .map_err(|e| e.to_string())
        })
        .as_ref()
        .map_err(|e| WorkspaceError::new("sql_worker", e.clone()))?;
    let (tx, rx) = mpsc::sync_channel(1);
    worker
        .send((text.to_owned(), id, formatting, tx))
        .map_err(|_| WorkspaceError::new("sql_worker", "SQL 工作器已退出"))?;
    rx.recv()
        .map_err(|_| WorkspaceError::new("sql_worker", "SQL 工作器已退出"))?
}
fn analyze_inner(text: &str, id: u32, formatting: bool) -> Result<Analysis, WorkspaceError> {
    if text.len() > MAX_BYTES || text.contains('\0') {
        return Err(WorkspaceError::new(
            "sql_budget",
            "SQL 离线检查限 256 KiB 且不含空字符",
        ));
    }
    let dialect = dialect(id)?;
    let map = SourceMap::new(text);
    let mut result = Analysis {
        diagnostics: Vec::new(),
        tables: Vec::new(),
        identifiers: Vec::new(),
        formatted: None,
    };
    let tokens = match Tokenizer::new(dialect.as_ref(), text).tokenize_with_location() {
        Ok(tokens) => tokens,
        Err(error) => {
            result.diagnostics.push(map.error(error.to_string()));
            return Ok(result);
        }
    };
    if tokens.len() > 30_000 {
        return Err(WorkspaceError::new(
            "sql_budget",
            "SQL token 数量超过 30000",
        ));
    }
    let mut nesting = 0usize;
    let mut complexity = 0usize;
    for token in &tokens {
        match &token.token {
            Token::LParen | Token::LBracket => {
                nesting += 1;
                complexity += 1;
            }
            Token::RParen | Token::RBracket => {
                nesting = nesting.saturating_sub(1);
            }
            Token::Word(w)
                if matches!(
                    w.keyword,
                    Keyword::AND
                        | Keyword::OR
                        | Keyword::NOT
                        | Keyword::CASE
                        | Keyword::WHEN
                        | Keyword::ELSE
                        | Keyword::WITH
                        | Keyword::SELECT
                        | Keyword::UNION
                        | Keyword::INTERSECT
                        | Keyword::EXCEPT
                        | Keyword::BEGIN
                ) =>
            {
                complexity += 1
            }
            Token::Word(_)
            | Token::Whitespace(_)
            | Token::Comma
            | Token::Period
            | Token::SemiColon
            | Token::Number(_, _)
            | Token::SingleQuotedString(_)
            | Token::DoubleQuotedString(_)
            | Token::EOF => {}
            _ => complexity += 1,
        }
        if nesting > 48 || complexity > 512 {
            return Err(WorkspaceError::new(
                "sql_budget",
                "SQL 嵌套或表达式复杂度超过离线预算",
            ));
        }
    }
    let parsed = Parser::new(dialect.as_ref())
        .with_recursion_limit(64)
        .with_tokens_with_locations(tokens.clone())
        .parse_statements();
    let statements = match parsed {
        Ok(statements) => statements,
        Err(error) => {
            result.diagnostics.push(map.error(error.to_string()));
            Vec::new()
        }
    };
    for statement in statements.iter().take(1000) {
        if let Statement::CreateTable(table) = statement {
            let ident = table.name.0.last().and_then(|p| p.as_ident());
            let range = ident
                .map(|i| map.range(i.span))
                .unwrap_or_else(|| map.range(Span::empty()));
            result.tables.push(Table {
                name: table_name(&table.name),
                quoted: table
                    .name
                    .0
                    .iter()
                    .any(|p| p.as_ident().is_some_and(|i| i.quote_style.is_some())),
                range,
                columns: table
                    .columns
                    .iter()
                    .take(1000)
                    .map(|column| Column {
                        name: column.name.value.clone(),
                        quoted: column.name.quote_style.is_some(),
                        detail: column.data_type.to_string().chars().take(256).collect(),
                        range: map.range(column.name.span),
                    })
                    .collect(),
            });
        }
    }
    for table in &result.tables {
        let relation = Relation {
            name: table.name.clone(),
            quoted: table.quoted,
        };
        result.identifiers.push(Identifier {
            name: table.name.clone(),
            quoted: table.quoted,
            role: "table",
            tables: vec![relation.clone()],
            range: table.range,
        });
        for column in &table.columns {
            result.identifiers.push(Identifier {
                name: column.name.clone(),
                quoted: column.quoted,
                role: "column",
                tables: vec![relation.clone()],
                range: column.range,
            });
        }
    }
    let mut bindings = Bindings {
        map: &map,
        identifiers: &mut result.identifiers,
        scopes: Vec::new(),
        ctes: Vec::new(),
        dialect: id,
    };
    for statement in &statements {
        let _ = statement.visit(&mut bindings);
    }
    // Resolve identifiers using dialect folding, while preserving source spans
    // and quote information for insertion. Other dialects depend on database
    // collation; use exact spelling rather than guess a case-insensitive match.
    for table in &mut result.tables {
        table.name = canonical_ident(&table.name, table.quoted, id);
        for column in &mut table.columns {
            column.name = canonical_ident(&column.name, column.quoted, id);
        }
    }
    for identifier in &mut result.identifiers {
        identifier.name = canonical_ident(&identifier.name, identifier.quoted, id);
        for relation in &mut identifier.tables {
            relation.name = canonical_ident(&relation.name, relation.quoted, id);
        }
    }
    if formatting && result.diagnostics.is_empty() {
        let formatted = format_tokens(&tokens, text, &map);
        // Refuse any formatter result that changes parsed SQL semantics. Raw
        // token slices preserve literals/quoted identifiers and comment bytes.
        let check = Parser::new(dialect.as_ref())
            .with_recursion_limit(64)
            .try_with_sql(&formatted)
            .and_then(|mut p| p.parse_statements());
        if check
            .as_ref()
            .ok()
            .map(|s| s.iter().map(ToString::to_string).collect::<Vec<_>>())
            == Some(
                statements
                    .iter()
                    .map(ToString::to_string)
                    .collect::<Vec<_>>(),
            )
        {
            result.formatted = Some(formatted);
        } else {
            return Err(WorkspaceError::new(
                "sql_format",
                "格式化无法保持语句结构，未修改文本",
            ));
        }
    }
    Ok(result)
}
struct Scope {
    relations: Vec<(Relation, Option<Ident>)>,
    unknown: bool,
    aliases: Vec<Ident>,
}
struct Bindings<'a> {
    map: &'a SourceMap,
    identifiers: &'a mut Vec<Identifier>,
    scopes: Vec<Scope>,
    ctes: Vec<Vec<String>>,
    dialect: u32,
}
fn canonical_ident(value: &str, quoted: bool, dialect: u32) -> String {
    if quoted {
        return value.to_owned();
    }
    match dialect {
        1 => value.to_ascii_lowercase(),
        7 | 8 => value.to_ascii_uppercase(),
        _ => value.to_owned(),
    }
}
fn same_ident(reference: &Ident, declaration: &str, quoted: bool, dialect: u32) -> bool {
    canonical_ident(&reference.value, reference.quote_style.is_some(), dialect)
        == canonical_ident(declaration, quoted, dialect)
}
impl Bindings<'_> {
    fn relation(&mut self, factor: &TableFactor, scope: &mut Scope) {
        if let TableFactor::Table {
            name,
            alias,
            args: None,
            ..
        } = factor
        {
            if name.0.len() > 1
                && name
                    .0
                    .iter()
                    .any(|p| p.as_ident().is_some_and(|i| i.quote_style.is_some()))
            {
                scope.unknown = true;
                return;
            }
            let full = table_name(name);
            if self
                .ctes
                .iter()
                .flatten()
                .any(|cte| cte.eq_ignore_ascii_case(&full))
            {
                scope.unknown = true;
                return;
            }
            if let Some(last) = name.0.last().and_then(|p| p.as_ident()) {
                let relation = Relation {
                    name: full.clone(),
                    quoted: last.quote_style.is_some(),
                };
                self.identifiers.push(Identifier {
                    name: full,
                    quoted: last.quote_style.is_some(),
                    role: "table",
                    tables: vec![relation.clone()],
                    range: self.map.range(last.span),
                });
                scope
                    .relations
                    .push((relation, alias.as_ref().map(|a| a.name.clone())));
            }
        } else {
            scope.unknown = true;
        }
    }
}
impl Visitor for Bindings<'_> {
    type Break = ();
    fn pre_visit_query(&mut self, query: &Query) -> ControlFlow<()> {
        self.ctes.push(
            query
                .with
                .as_ref()
                .map(|w| {
                    w.cte_tables
                        .iter()
                        .map(|c| c.alias.name.value.clone())
                        .collect()
                })
                .unwrap_or_default(),
        );
        ControlFlow::Continue(())
    }
    fn post_visit_query(&mut self, _: &Query) -> ControlFlow<()> {
        self.ctes.pop();
        ControlFlow::Continue(())
    }
    fn pre_visit_select(&mut self, select: &Select) -> ControlFlow<()> {
        let mut scope = Scope {
            relations: Vec::new(),
            unknown: false,
            aliases: select
                .projection
                .iter()
                .filter_map(|p| {
                    if let sqlparser::ast::SelectItem::ExprWithAlias { alias, .. } = p {
                        Some(alias.clone())
                    } else {
                        None
                    }
                })
                .collect(),
        };
        for from in &select.from {
            self.relation(&from.relation, &mut scope);
            for join in &from.joins {
                self.relation(&join.relation, &mut scope);
            }
        }
        self.scopes.push(scope);
        ControlFlow::Continue(())
    }
    fn post_visit_select(&mut self, _: &Select) -> ControlFlow<()> {
        self.scopes.pop();
        ControlFlow::Continue(())
    }
    fn pre_visit_expr(&mut self, expr: &Expr) -> ControlFlow<()> {
        let (ident, tables) = match expr {
            Expr::Identifier(ident) => {
                let Some(scope) = self.scopes.last() else {
                    return ControlFlow::Continue(());
                };
                if scope.unknown
                    || scope
                        .aliases
                        .iter()
                        .any(|a| same_ident(ident, &a.value, a.quote_style.is_some(), self.dialect))
                    || scope.relations.is_empty()
                {
                    return ControlFlow::Continue(());
                }
                (
                    ident,
                    scope.relations.iter().map(|(r, _)| r.clone()).collect(),
                )
            }
            Expr::CompoundIdentifier(parts) if parts.len() == 2 => {
                let mut candidates = Vec::new();
                for scope in self.scopes.iter().rev() {
                    if scope.unknown {
                        return ControlFlow::Continue(());
                    }
                    for (relation, alias) in &scope.relations {
                        let matched = if let Some(alias) = alias {
                            same_ident(
                                &parts[0],
                                &alias.value,
                                alias.quote_style.is_some(),
                                self.dialect,
                            )
                        } else {
                            same_ident(
                                &parts[0],
                                relation.name.rsplit('.').next().unwrap_or(&relation.name),
                                relation.quoted,
                                self.dialect,
                            )
                        };
                        if matched {
                            candidates.push(relation.clone());
                        }
                    }
                    if !candidates.is_empty() {
                        break;
                    }
                }
                if candidates.len() != 1 {
                    return ControlFlow::Continue(());
                }
                (&parts[1], candidates)
            }
            _ => return ControlFlow::Continue(()),
        };
        self.identifiers.push(Identifier {
            name: ident.value.clone(),
            quoted: ident.quote_style.is_some(),
            role: "column",
            tables,
            range: self.map.range(ident.span),
        });
        ControlFlow::Continue(())
    }
}
fn format_tokens(tokens: &[TokenWithSpan], text: &str, map: &SourceMap) -> String {
    let eol = if text.contains("\r\n") {
        "\r\n"
    } else if text.contains('\r') && !text.contains('\n') {
        "\r"
    } else {
        "\n"
    };
    let mut out = String::new();
    let mut depth = 0usize;
    let mut previous = "";
    for item in tokens {
        let raw = map.raw(item.span, text);
        match &item.token {
            Token::Whitespace(Whitespace::SingleLineComment { .. })
            | Token::Whitespace(Whitespace::MultiLineComment(_)) => {
                if !out.is_empty() && !out.ends_with(['\r', '\n', ' ']) {
                    out.push(' ');
                }
                out.push_str(raw);
                if !out.ends_with(['\r', '\n']) {
                    out.push_str(eol);
                }
                previous = "";
            }
            Token::Whitespace(_) | Token::EOF => continue,
            _ => {
                let upper = match &item.token {
                    Token::Word(word)
                        if word.quote_style.is_none() && word.keyword != Keyword::NoKeyword =>
                    {
                        word.value.to_ascii_uppercase()
                    }
                    _ => raw.to_string(),
                };
                let block = depth == 0
                    && [
                        "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
                        "GROUP", "ORDER", "HAVING", "LIMIT", "UNION", "INSERT", "UPDATE", "DELETE",
                        "CREATE", "ALTER", "DROP",
                    ]
                    .contains(&upper.as_str());
                if block && !out.is_empty() && !out.ends_with(['\r', '\n']) {
                    out.truncate(out.trim_end_matches(' ').len());
                    out.push_str(eol);
                }
                if [")", ",", ";", "."].contains(&raw) {
                    out.truncate(out.trim_end_matches(' ').len());
                } else if !out.is_empty()
                    && !out.ends_with(['\r', '\n', ' '])
                    && previous != "("
                    && previous != "."
                {
                    out.push(' ');
                }
                out.push_str(raw);
                if raw == "(" {
                    depth += 1;
                }
                if raw == ")" {
                    depth = depth.saturating_sub(1);
                }
                if raw == ";" {
                    out.push_str(eol);
                }
                previous = raw;
            }
        }
    }
    let mut out = out.trim_end_matches(['\r', '\n', ' ']).to_string();
    if !out.is_empty() {
        out.push_str(eol);
    }
    out
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dialect_ddl_unicode_and_errors() {
        let text = "-- 😀\r\nCREATE TABLE \"用户\" (\"名字\" TEXT, id INTEGER);\r\nSELECT \"名字\" FROM \"用户\";";
        let result = analyze(text, 1, true).unwrap();
        assert!(result.diagnostics.is_empty());
        assert_eq!(result.tables[0].name, "用户");
        assert_eq!(result.tables[0].columns[0].range.start.line, 1);
        assert!(result.formatted.unwrap().contains("-- 😀\r\n"));
        let bad = analyze("select * from ;", 1, false).unwrap();
        assert_eq!(bad.diagnostics.len(), 1);
        assert!(bad.diagnostics[0].range.start.character > 0);
        assert!(
            analyze("select `name` from users;", 2, false)
                .unwrap()
                .diagnostics
                .is_empty()
        );
        assert!(
            !analyze("select `name` from users;", 1, false)
                .unwrap()
                .diagnostics
                .is_empty()
        );
    }
    #[test]
    fn bound_ast_lifecycle_and_scope() {
        assert!(analyze(&format!("select {}1", "a+".repeat(600)), 0, false).is_err());
        assert!(analyze(&format!("select {}1;", "a+".repeat(200)), 0, true).is_ok());
        let result = analyze(
            "create table users(id int); select u.id from users u; select id from missing_table;",
            0,
            false,
        )
        .unwrap();
        let refs = result
            .identifiers
            .iter()
            .filter(|i| i.role == "column" && i.name == "id")
            .collect::<Vec<_>>();
        assert!(
            refs.iter()
                .any(|i| i.tables.iter().any(|r| r.name == "users"))
        );
        assert!(
            refs.iter()
                .any(|i| i.tables.iter().any(|r| r.name == "missing_table"))
        );
    }
    #[test]
    fn preserve_comments_and_literals_and_boundaries() {
        let text = "/*keep*/ select 'a  b', 'c''d', 100 --hello\nfrom users where id=2;";
        let formatted = analyze(text, 0, true).unwrap().formatted.unwrap();
        for fragment in ["/*keep*/", "'a  b'", "'c''d'", "--hello"] {
            assert!(formatted.contains(fragment));
        }
        assert!(analyze(&" ".repeat(MAX_BYTES + 1), 0, false).is_err());
        assert!(analyze("select 1", 99, false).is_err());
        assert!(analyze(&format!("select {}1", "(".repeat(70)), 1, false).is_err());
    }
}
