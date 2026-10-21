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
}

pub struct Grammar {
    pub language: Language,
    pub query: Query,
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
        }
    }
    pub fn grammar(self) -> Result<Arc<Grammar>, WorkspaceError> {
        static CACHE: OnceLock<Mutex<HashMap<SyntaxLanguage, Arc<Grammar>>>> = OnceLock::new();
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
