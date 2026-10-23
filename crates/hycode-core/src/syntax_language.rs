use crate::WorkspaceError;
use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex, OnceLock},
};
use tree_sitter::{Language, Query};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SyntaxLanguage {
    Dart,
    JavaScript,
    TypeScript,
    Tsx,
    Html,
    Vue,
    Css,
    Json,
    Yaml,
    Toml,
    C,
    Cpp,
    Rust,
    Swift,
    Java,
    Sql,
}

pub struct Grammar {
    pub language: Language,
    pub query: Query,
}

static CACHE: OnceLock<Mutex<HashMap<SyntaxLanguage, Arc<Grammar>>>> = OnceLock::new();

/// Release only cache-owned grammars. Active parsers keep their Arc, avoiding
/// cold compilation for the currently used language. Drop outside the lock.
pub fn trim_cache(
    path: &str,
    token: Option<&crate::HyCodeCancellation>,
) -> Result<usize, WorkspaceError> {
    let Some(cache) = CACHE.get() else {
        return Ok(0);
    };
    let mut cache = cache
        .lock()
        .map_err(|_| WorkspaceError::new("syntax_unavailable", "语法缓存不可用"))?;
    if token.is_some_and(crate::HyCodeCancellation::is_cancelled) {
        return Err(WorkspaceError::new("cancelled", "缓存清理已取消"));
    }
    let protected = SyntaxLanguage::for_path(path);
    let keys: Vec<_> = cache
        .iter()
        .filter(|(kind, grammar)| {
            // Fragment and embedded-language parsers are temporary; their query
            // Arc may be cache-only even while this language is on screen.
            let active = protected == Some(**kind)
                || matches!(protected, Some(SyntaxLanguage::Html | SyntaxLanguage::Vue))
                    && matches!(
                        kind,
                        SyntaxLanguage::JavaScript
                            | SyntaxLanguage::TypeScript
                            | SyntaxLanguage::Tsx
                            | SyntaxLanguage::Css
                    );
            !active && Arc::strong_count(grammar) == 1
        })
        .map(|(kind, _)| *kind)
        .collect();
    let removed: Vec<_> = keys.iter().filter_map(|kind| cache.remove(kind)).collect();
    drop(cache);
    let count = removed.len();
    drop(removed);
    Ok(count)
}

impl SyntaxLanguage {
    pub fn for_path(path: &str) -> Option<Self> {
        Some(
            match Path::new(path)
                .extension()?
                .to_str()?
                .to_ascii_lowercase()
                .as_str()
            {
                "dart" => Self::Dart,
                "js" | "jsx" | "mjs" | "cjs" => Self::JavaScript,
                "ts" | "mts" | "cts" => Self::TypeScript,
                "tsx" => Self::Tsx,
                "html" | "htm" => Self::Html,
                "vue" => Self::Vue,
                "css" => Self::Css,
                "json" => Self::Json,
                "yaml" | "yml" => Self::Yaml,
                "toml" => Self::Toml,
                "c" | "h" => Self::C,
                "cc" | "cpp" | "cxx" | "hpp" | "hh" | "hxx" => Self::Cpp,
                "rs" => Self::Rust,
                "swift" => Self::Swift,
                "java" => Self::Java,
                "sql" => Self::Sql,
                _ => return None,
            },
        )
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::Dart => "Dart",
            Self::JavaScript => "JavaScript / JSX",
            Self::TypeScript => "TypeScript",
            Self::Tsx => "TSX",
            Self::Html => "HTML",
            Self::Vue => "Vue",
            Self::Css => "CSS",
            Self::Json => "JSON",
            Self::Yaml => "YAML",
            Self::Toml => "TOML",
            Self::C => "C",
            Self::Cpp => "C++",
            Self::Rust => "Rust",
            Self::Swift => "Swift",
            Self::Java => "Java",
            Self::Sql => "SQL",
        }
    }
    pub fn grammar(self) -> Result<Arc<Grammar>, WorkspaceError> {
        let mut cache = CACHE
            .get_or_init(Default::default)
            .lock()
            .map_err(|_| WorkspaceError::new("syntax_unavailable", "语法缓存不可用"))?;
        if let Some(grammar) = cache.get(&self) {
            return Ok(grammar.clone());
        }
        let (language, query): (Language, String) = match self {
            Self::Dart => (
                tree_sitter_dart::LANGUAGE.into(),
                tree_sitter_dart::HIGHLIGHTS_QUERY.into(),
            ),
            Self::JavaScript => (
                tree_sitter_javascript::LANGUAGE.into(),
                format!(
                    "{}\n{}",
                    tree_sitter_javascript::HIGHLIGHT_QUERY,
                    tree_sitter_javascript::JSX_HIGHLIGHT_QUERY
                ),
            ),
            Self::TypeScript | Self::Tsx => (
                if self == Self::Tsx {
                    tree_sitter_typescript::LANGUAGE_TSX.into()
                } else {
                    tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into()
                },
                format!(
                    "{}\n{}\n{}",
                    tree_sitter_javascript::HIGHLIGHT_QUERY,
                    if self == Self::Tsx {
                        tree_sitter_javascript::JSX_HIGHLIGHT_QUERY
                    } else {
                        ""
                    },
                    tree_sitter_typescript::HIGHLIGHTS_QUERY
                ),
            ),
            Self::Html => (
                tree_sitter_html::LANGUAGE.into(),
                tree_sitter_html::HIGHLIGHTS_QUERY.into(),
            ),
            // The Vue crate exposes a parser, but does not export its nested editor queries.
            // Use the HTML query plus our small directive query; no private editor resources.
            Self::Vue => (
                tree_sitter_vue_next::LANGUAGE.into(),
                format!(
                    "{}\n(directive_name) @attribute\n(directive_value) @variable\n",
                    tree_sitter_html::HIGHLIGHTS_QUERY
                ),
            ),
            Self::Css => (
                tree_sitter_css::LANGUAGE.into(),
                tree_sitter_css::HIGHLIGHTS_QUERY.into(),
            ),
            Self::Json => (
                tree_sitter_json::LANGUAGE.into(),
                tree_sitter_json::HIGHLIGHTS_QUERY.into(),
            ),
            Self::Yaml => (
                tree_sitter_yaml::LANGUAGE.into(),
                tree_sitter_yaml::HIGHLIGHTS_QUERY.into(),
            ),
            Self::Toml => (
                tree_sitter_toml_ng::LANGUAGE.into(),
                tree_sitter_toml_ng::HIGHLIGHTS_QUERY.into(),
            ),
            Self::C => (
                tree_sitter_c::LANGUAGE.into(),
                tree_sitter_c::HIGHLIGHT_QUERY.into(),
            ),
            Self::Cpp => (
                tree_sitter_cpp::LANGUAGE.into(),
                format!(
                    "{}\n{}",
                    tree_sitter_c::HIGHLIGHT_QUERY,
                    tree_sitter_cpp::HIGHLIGHT_QUERY
                ),
            ),
            Self::Swift => (
                tree_sitter_swift::LANGUAGE.into(),
                tree_sitter_swift::HIGHLIGHTS_QUERY.into(),
            ),
            Self::Java => (
                tree_sitter_java::LANGUAGE.into(),
                tree_sitter_java::HIGHLIGHTS_QUERY.into(),
            ),
            Self::Sql => (
                tree_sitter_sequel::LANGUAGE.into(),
                tree_sitter_sequel::HIGHLIGHTS_QUERY.into(),
            ),
            Self::Rust => (
                tree_sitter_rust::LANGUAGE.into(),
                tree_sitter_rust::HIGHLIGHTS_QUERY.into(),
            ),
        };
        let query = Query::new(&language, &query)
            .map_err(|error| WorkspaceError::new("syntax_query", error.to_string()))?;
        let grammar = Arc::new(Grammar { language, query });
        cache.insert(self, grammar.clone());
        Ok(grammar)
    }
}

#[cfg(test)]
mod cache_tests {
    use super::*;
    #[test]
    fn active_grammars_remain_owned_and_unused_ones_can_be_rebuilt() {
        let grammar = SyntaxLanguage::Dart.grammar().unwrap();
        let weak = Arc::downgrade(&grammar);
        trim_cache("", None).unwrap();
        assert!(weak.upgrade().is_some());
        assert!(Arc::ptr_eq(
            &grammar,
            &SyntaxLanguage::Dart.grammar().unwrap()
        ));
        drop(grammar);
        trim_cache("active.dart", None).unwrap();
        assert!(weak.upgrade().is_some());
        assert!(trim_cache("", None).unwrap() >= 1);
        assert!(weak.upgrade().is_none());
        assert!(SyntaxLanguage::Dart.grammar().is_ok());
    }

    #[test]
    fn fragment_and_embedded_queries_remain_warm_for_the_active_path() {
        let languages = [
            SyntaxLanguage::Vue,
            SyntaxLanguage::JavaScript,
            SyntaxLanguage::TypeScript,
            SyntaxLanguage::Tsx,
            SyntaxLanguage::Css,
        ];
        let weak: Vec<_> = languages
            .into_iter()
            .map(|kind| Arc::downgrade(&kind.grammar().unwrap()))
            .collect();
        trim_cache("active.vue", None).unwrap();
        assert!(weak.iter().all(|item| item.upgrade().is_some()));
        trim_cache("", None).unwrap();
        assert!(weak.iter().all(|item| item.upgrade().is_none()));
    }
}
