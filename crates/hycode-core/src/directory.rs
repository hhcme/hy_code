use serde::Serialize;
use std::fs;
use std::path::{Component, Path};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::UNIX_EPOCH;

pub const MAX_ENTRIES: usize = 20_000;
const MAX_SCANNED: usize = 50_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EntryKind {
    Directory,
    File,
    Symlink,
    Other,
}

#[derive(Debug, Serialize)]
pub struct Entry {
    pub name: String,
    pub relative_path: String,
    pub kind: EntryKind,
    pub size: Option<u64>,
    pub modified_ms: Option<u64>,
}

#[derive(Debug, Serialize)]
pub struct DirectorySnapshot {
    pub relative_path: String,
    pub entries: Vec<Entry>,
    pub skipped: usize,
    pub truncated: bool,
}

#[derive(Debug, Serialize)]
pub struct WorkspaceError {
    pub code: &'static str,
    pub message: String,
}

impl WorkspaceError {
    pub(crate) fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}

fn check_cancelled(cancelled: &AtomicBool) -> Result<(), WorkspaceError> {
    if cancelled.load(Ordering::Relaxed) {
        return Err(WorkspaceError::new("cancelled", "目录读取已取消"));
    }
    Ok(())
}

/// Enumerate exactly one directory. Symlinks are visible but are never traversed.
/// This is a read-only desktop policy, not a filesystem sandbox against concurrent renames.
pub fn list_directory(
    root: &Path,
    relative: &Path,
    include_hidden: bool,
    cancelled: &AtomicBool,
) -> Result<DirectorySnapshot, WorkspaceError> {
    list_with_budget(
        root,
        relative,
        include_hidden,
        cancelled,
        MAX_ENTRIES,
        MAX_SCANNED,
    )
}

fn list_with_budget(
    root: &Path,
    relative: &Path,
    include_hidden: bool,
    cancelled: &AtomicBool,
    max_entries: usize,
    max_scanned: usize,
) -> Result<DirectorySnapshot, WorkspaceError> {
    check_cancelled(cancelled)?;
    if relative
        .components()
        .any(|part| !matches!(part, Component::Normal(_) | Component::CurDir))
    {
        return Err(WorkspaceError::new(
            "invalid_path",
            "目录路径必须位于当前项目内",
        ));
    }
    let root = root
        .canonicalize()
        .map_err(|e| WorkspaceError::new("root_unavailable", e.to_string()))?;
    if !root.is_dir() {
        return Err(WorkspaceError::new("not_directory", "选择的项目不是目录"));
    }
    let mut directory = root.clone();
    for part in relative.components() {
        directory.push(part);
        let metadata = fs::symlink_metadata(&directory)
            .map_err(|e| WorkspaceError::new("directory_unavailable", e.to_string()))?;
        if metadata.file_type().is_symlink() {
            return Err(WorkspaceError::new(
                "symlink_not_followed",
                "当前浏览不跟随符号链接",
            ));
        }
    }
    let canonical = directory
        .canonicalize()
        .map_err(|e| WorkspaceError::new("directory_unavailable", e.to_string()))?;
    if !canonical.starts_with(&root) {
        return Err(WorkspaceError::new(
            "outside_workspace",
            "目录不在当前项目内",
        ));
    }
    let children = fs::read_dir(&canonical)
        .map_err(|e| WorkspaceError::new("directory_unavailable", e.to_string()))?;
    let normalized = relative
        .components()
        .filter_map(|part| match part {
            Component::Normal(name) => name.to_str(),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/");
    let mut snapshot = DirectorySnapshot {
        relative_path: normalized.clone(),
        entries: Vec::new(),
        skipped: 0,
        truncated: false,
    };
    for (scanned, child) in children.enumerate() {
        check_cancelled(cancelled)?;
        if scanned >= max_scanned || snapshot.entries.len() >= max_entries {
            snapshot.truncated = true;
            break;
        }
        let child = match child {
            Ok(child) => child,
            Err(_) => {
                snapshot.skipped += 1;
                continue;
            }
        };
        let name = match child.file_name().into_string() {
            Ok(name) => name,
            Err(_) => {
                snapshot.skipped += 1;
                continue;
            }
        };
        if !include_hidden && name.starts_with('.') {
            continue;
        }
        let metadata = match fs::symlink_metadata(child.path()) {
            Ok(metadata) => metadata,
            Err(_) => {
                snapshot.skipped += 1;
                continue;
            }
        };
        let kind = if metadata.is_dir() {
            EntryKind::Directory
        } else if metadata.is_file() {
            EntryKind::File
        } else if metadata.file_type().is_symlink() {
            EntryKind::Symlink
        } else {
            EntryKind::Other
        };
        let relative_path = if normalized.is_empty() {
            name.clone()
        } else {
            format!("{normalized}/{name}")
        };
        snapshot.entries.push(Entry {
            name,
            relative_path,
            kind,
            size: (kind == EntryKind::File).then_some(metadata.len()),
            modified_ms: metadata
                .modified()
                .ok()
                .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
                .and_then(|duration| u64::try_from(duration.as_millis()).ok()),
        });
    }
    snapshot.entries.sort_by_cached_key(|entry| {
        (
            entry.kind != EntryKind::Directory,
            entry.name.to_lowercase(),
            entry.name.clone(),
        )
    });
    check_cancelled(cancelled)?;
    Ok(snapshot)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicU64;

    static NEXT_ID: AtomicU64 = AtomicU64::new(0);
    struct Fixture(std::path::PathBuf);
    impl Fixture {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "hycode-core-{}-{}",
                std::process::id(),
                NEXT_ID.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn lists_one_level_sorted_with_unicode_and_hidden_policy() {
        let fixture = Fixture::new();
        fs::create_dir(fixture.0.join("src")).unwrap();
        fs::write(fixture.0.join("src/nested.rs"), "ignored until expanded").unwrap();
        fs::write(fixture.0.join("中文😀.swift"), "hello").unwrap();
        fs::write(fixture.0.join(".hidden"), "hidden").unwrap();
        let cancel = AtomicBool::new(false);
        let snapshot = list_directory(&fixture.0, Path::new(""), false, &cancel).unwrap();
        assert_eq!(snapshot.entries.len(), 2);
        assert_eq!(snapshot.entries[0].kind, EntryKind::Directory);
        assert_eq!(snapshot.entries[1].relative_path, "中文😀.swift");
        assert_eq!(snapshot.entries[1].size, Some(5));
        assert_eq!(
            list_directory(&fixture.0, Path::new(""), true, &cancel)
                .unwrap()
                .entries
                .len(),
            3
        );
        assert_eq!(
            list_directory(&fixture.0, Path::new("src"), false, &cancel)
                .unwrap()
                .entries[0]
                .relative_path,
            "src/nested.rs"
        );
    }

    #[test]
    fn rejects_parent_absolute_missing_and_cancelled_requests() {
        let fixture = Fixture::new();
        let cancel = AtomicBool::new(false);
        for path in ["../", "/tmp", "src/../../"] {
            assert_eq!(
                list_directory(&fixture.0, Path::new(path), false, &cancel)
                    .unwrap_err()
                    .code,
                "invalid_path"
            );
        }
        assert!(list_directory(&fixture.0, Path::new("missing"), false, &cancel).is_err());
        cancel.store(true, Ordering::Relaxed);
        assert_eq!(
            list_directory(&fixture.0, Path::new(""), false, &cancel)
                .unwrap_err()
                .code,
            "cancelled"
        );
    }

    #[cfg(unix)]
    #[test]
    fn shows_links_but_never_expands_them() {
        use std::os::unix::fs::symlink;
        let fixture = Fixture::new();
        let outside = Fixture::new();
        symlink(&outside.0, fixture.0.join("outside")).unwrap();
        let cancel = AtomicBool::new(false);
        let snapshot = list_directory(&fixture.0, Path::new(""), true, &cancel).unwrap();
        assert_eq!(snapshot.entries.len(), 1);
        assert_eq!(snapshot.entries[0].kind, EntryKind::Symlink);
        assert_eq!(snapshot.skipped, 0);
        assert_eq!(
            list_directory(&fixture.0, Path::new("outside"), true, &cancel)
                .unwrap_err()
                .code,
            "symlink_not_followed"
        );
    }

    #[test]
    fn reports_budget_limits_instead_of_claiming_a_complete_listing() {
        let fixture = Fixture::new();
        for name in ["a", "b", "c"] {
            fs::write(fixture.0.join(name), "").unwrap();
        }
        let snapshot = list_with_budget(
            &fixture.0,
            Path::new(""),
            true,
            &AtomicBool::new(false),
            2,
            10,
        )
        .unwrap();
        assert_eq!(snapshot.entries.len(), 2);
        assert!(snapshot.truncated);
    }
}
