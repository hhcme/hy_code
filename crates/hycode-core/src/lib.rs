//! Workspace discovery and revisioned text buffers; no UI or process execution.
mod directory;
mod document;
mod document_ffi;
mod ffi;
mod syntax;
mod syntax_language;
#[cfg(test)]
mod syntax_tests;

pub use directory::{DirectorySnapshot, Entry, EntryKind, WorkspaceError, list_directory};
pub use document_ffi::*;
pub use ffi::*;
