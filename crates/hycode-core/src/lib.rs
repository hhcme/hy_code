//! Read-only workspace discovery. The caller schedules blocking I/O off the UI thread.
mod directory;
mod ffi;

pub use directory::{DirectorySnapshot, Entry, EntryKind, WorkspaceError, list_directory};
pub use ffi::*;
