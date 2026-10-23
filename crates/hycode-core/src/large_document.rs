//! Disk-backed byte piece table. A bounded native page is an input projection;
//! this serial owner alone holds edits/history. No mmap: external truncation
//! must produce an ordinary error, never SIGBUS. All offsets are 64-bit bytes in
//! the original encoding, excluding BOM. Never materializes the complete file.
use crate::{HyCodeCancellation, WorkspaceError};
use serde::Serialize;
use std::{
    collections::HashSet,
    fs::{File, Metadata},
    os::{
        fd::BorrowedFd,
        unix::fs::{FileExt, MetadataExt},
    },
    sync::Arc,
};

pub const PAGE_BYTES: usize = 64 * 1024;
const MAX_EDIT: usize = 1024 * 1024;
const MAX_RESIDENT: usize = 64 * 1024 * 1024;
const MAX_PIECES: usize = 65_536;
const MAX_HISTORY: usize = 128;
const MAX_HISTORY_BYTES: u64 = 32 * 1024 * 1024;
const IO_CHUNK: usize = 256 * 1024;

fn error(code: &'static str, message: &str) -> WorkspaceError {
    WorkspaceError::new(code, message)
}
fn io(error: std::io::Error) -> WorkspaceError {
    self::error("large_file_io", &error.to_string())
}
pub(crate) fn check(token: Option<&HyCodeCancellation>) -> Result<(), WorkspaceError> {
    if token.is_some_and(HyCodeCancellation::is_cancelled) {
        Err(error("cancelled", "大文件任务已取消"))
    } else {
        Ok(())
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
struct Version {
    dev: u64,
    ino: u64,
    size: u64,
    modified: (i64, i64),
    changed: (i64, i64),
    links: u64,
}
impl Version {
    fn of(m: &Metadata) -> Self {
        Self {
            dev: m.dev(),
            ino: m.ino(),
            size: m.len(),
            modified: (m.mtime(), m.mtime_nsec()),
            changed: (m.ctime(), m.ctime_nsec()),
            links: m.nlink(),
        }
    }
}
struct Source {
    file: File,
    version: Version,
}
impl Source {
    fn new(file: File) -> Result<Arc<Self>, WorkspaceError> {
        let info = file.metadata().map_err(io)?;
        if !info.is_file() || info.nlink() != 1 {
            return Err(error("not_regular", "只支持无额外硬链接的普通文件"));
        }
        Ok(Arc::new(Self {
            file,
            version: Version::of(&info),
        }))
    }
    fn verify(&self) -> Result<(), WorkspaceError> {
        if Version::of(&self.file.metadata().map_err(io)?) != self.version {
            return Err(error(
                "external_change",
                "大文件的磁盘来源已变化；编辑已保留，未覆盖文件",
            ));
        }
        Ok(())
    }
}
#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
enum Encoding {
    Utf8,
    Utf16Le,
    Utf16Be,
}
impl Encoding {
    fn decode(self, bytes: &[u8]) -> Result<String, WorkspaceError> {
        let value = match self {
            Self::Utf8 => std::str::from_utf8(bytes)
                .map(str::to_owned)
                .map_err(|_| error("invalid_encoding", "此片段不是有效 UTF-8；未修改磁盘"))?,
            Self::Utf16Le | Self::Utf16Be => {
                if !bytes.len().is_multiple_of(2) {
                    return Err(error("invalid_encoding", "UTF-16 片段长度无效"));
                }
                let units: Vec<_> = bytes
                    .chunks_exact(2)
                    .map(|b| {
                        if matches!(self, Self::Utf16Le) {
                            u16::from_le_bytes([b[0], b[1]])
                        } else {
                            u16::from_be_bytes([b[0], b[1]])
                        }
                    })
                    .collect();
                String::from_utf16(&units)
                    .map_err(|_| error("invalid_encoding", "此片段包含无效 UTF-16 字符"))?
            }
        };
        if value.contains('\0') {
            return Err(error("binary_file", "此片段包含空字符，不能作为纯文本编辑"));
        }
        Ok(value)
    }
    fn encode(self, text: &str) -> Vec<u8> {
        match self {
            Self::Utf8 => text.as_bytes().to_vec(),
            _ => text
                .encode_utf16()
                .flat_map(|u| {
                    if matches!(self, Self::Utf16Le) {
                        u.to_le_bytes()
                    } else {
                        u.to_be_bytes()
                    }
                })
                .collect(),
        }
    }
    fn width(self, character: char) -> usize {
        if matches!(self, Self::Utf8) {
            character.len_utf8()
        } else {
            character.len_utf16() * 2
        }
    }
}
#[derive(Clone)]
enum Backing {
    File(Arc<Source>),
    Insert(Arc<[u8]>),
}
#[derive(Clone)]
struct Piece {
    backing: Backing,
    start: u64,
    len: u64,
}
impl Piece {
    fn part(&self, start: u64, end: u64) -> Self {
        Self {
            backing: self.backing.clone(),
            start: self.start + start,
            len: end - start,
        }
    }
}
#[derive(Clone)]
struct Edit {
    at: u64,
    removed: Vec<Piece>,
    inserted: Vec<Piece>,
}
impl Edit {
    fn removed_len(&self) -> u64 {
        self.removed.iter().map(|p| p.len).sum()
    }
    fn inserted_len(&self) -> u64 {
        self.inserted.iter().map(|p| p.len).sum()
    }
}
#[derive(Serialize)]
pub struct LargePage {
    pub text: String,
    pub start: u64,
    pub end: u64,
    pub total_bytes: u64,
    encoding: Encoding,
    has_bom: bool,
    line_ending: &'static str,
    pub can_undo: bool,
    pub can_redo: bool,
    pub remaining_bytes: usize,
    pub remaining_pieces: usize,
}
#[derive(Serialize)]
pub struct LargeStatus {
    pub total_bytes: u64,
    pub can_undo: bool,
    pub can_redo: bool,
    pub remaining_bytes: usize,
    pub remaining_pieces: usize,
}
struct Window {
    start: u64,
    text: String,
}
pub struct LargeDocument {
    pieces: Vec<Piece>,
    length: u64,
    encoding: Encoding,
    bom: Vec<u8>,
    revision: u64,
    undo: Vec<Edit>,
    redo: Vec<Edit>,
    window: Option<Window>,
    syntax: Option<crate::syntax::SyntaxState>,
}
impl LargeDocument {
    /// Caller must lend a valid read descriptor until this synchronous call
    /// returns. Clone owns its lifetime independently; paths are host-authorized.
    pub unsafe fn open(fd: i32) -> Result<Self, WorkspaceError> {
        let file = File::from(
            unsafe { BorrowedFd::borrow_raw(fd) }
                .try_clone_to_owned()
                .map_err(io)?,
        );
        let source = Source::new(file)?;
        let size = source.file.metadata().map_err(io)?.len();
        let mut head = vec![0; size.min(8) as usize];
        read_exact(&source.file, &mut head, 0)?;
        if head.starts_with(b"%PDF-") || head.starts_with(b"PK\x03\x04") {
            return Err(error("binary_file", "此文件不是纯文本"));
        }
        if head.starts_with(&[0xff, 0xfe, 0, 0]) || head.starts_with(&[0, 0, 0xfe, 0xff]) {
            return Err(error("unsupported_encoding", "暂不支持 UTF-32"));
        }
        let (encoding, bom) = if head.starts_with(&[0xff, 0xfe]) {
            (Encoding::Utf16Le, vec![0xff, 0xfe])
        } else if head.starts_with(&[0xfe, 0xff]) {
            (Encoding::Utf16Be, vec![0xfe, 0xff])
        } else if head.starts_with(&[0xef, 0xbb, 0xbf]) {
            (Encoding::Utf8, vec![0xef, 0xbb, 0xbf])
        } else {
            (Encoding::Utf8, vec![])
        };
        let length = size - bom.len() as u64;
        if !matches!(encoding, Encoding::Utf8) && !length.is_multiple_of(2) {
            return Err(error("invalid_encoding", "UTF-16 文件长度无效"));
        }
        let pieces = if length == 0 {
            vec![]
        } else {
            vec![Piece {
                backing: Backing::File(source),
                start: bom.len() as u64,
                len: length,
            }]
        };
        Ok(Self {
            pieces,
            length,
            encoding,
            bom,
            revision: 0,
            undo: vec![],
            redo: vec![],
            window: None,
            syntax: None,
        })
    }
    pub fn revision(&self) -> u64 {
        self.revision
    }
    fn expect(&self, revision: u64) -> Result<(), WorkspaceError> {
        if self.revision != revision {
            Err(error("stale_revision", "大文件修订已变化，拒绝过期操作"))
        } else {
            Ok(())
        }
    }
    fn sources(&self, history: bool) -> Vec<Arc<Source>> {
        let mut seen = HashSet::new();
        let mut sources = vec![];
        let history_pieces = self
            .undo
            .iter()
            .chain(&self.redo)
            .flat_map(|e| e.removed.iter().chain(&e.inserted));
        for p in self.pieces.iter().chain(history_pieces.filter(|_| history)) {
            if let Backing::File(s) = &p.backing
                && seen.insert(Arc::as_ptr(s))
            {
                sources.push(s.clone());
            }
        }
        sources
    }
    fn read(
        &self,
        start: u64,
        len: usize,
        token: Option<&HyCodeCancellation>,
    ) -> Result<Vec<u8>, WorkspaceError> {
        if start > self.length || len as u64 > self.length - start {
            return Err(error("invalid_range", "片段越界"));
        }
        let mut bytes = vec![0; len];
        let mut base = 0;
        for piece in &self.pieces {
            check(token)?;
            let a = base.max(start);
            let b = (base + piece.len).min(start + len as u64);
            if a < b {
                let from = piece.start + a - base;
                let dest = &mut bytes[(a - start) as usize..(b - start) as usize];
                match &piece.backing {
                    Backing::File(s) => read_exact(&s.file, dest, from)?,
                    Backing::Insert(data) => {
                        dest.copy_from_slice(&data[from as usize..from as usize + dest.len()])
                    }
                }
            }
            base += piece.len;
            if base >= start + len as u64 {
                break;
            }
        }
        Ok(bytes)
    }
    fn verify(&self) -> Result<(), WorkspaceError> {
        for s in self.sources(false) {
            s.verify()?;
        }
        Ok(())
    }
    pub fn page(
        &mut self,
        revision: u64,
        requested: u64,
        token: Option<&HyCodeCancellation>,
    ) -> Result<LargePage, WorkspaceError> {
        self.expect(revision)?;
        check(token)?;
        self.verify()?;
        let requested = requested.min(self.length);
        let base = requested.saturating_sub(4)
            & if matches!(self.encoding, Encoding::Utf8) {
                u64::MAX
            } else {
                !1
            };
        let size = (self.length - base).min((PAGE_BYTES + 16) as u64) as usize;
        let bytes = self.read(base, size, token)?;
        let mut a = (requested - base) as usize;
        if matches!(self.encoding, Encoding::Utf8) {
            while a < bytes.len() && bytes[a] & 0xc0 == 0x80 {
                a += 1;
            }
        } else {
            a = a.next_multiple_of(2);
            if a + 1 < bytes.len() {
                let unit = if matches!(self.encoding, Encoding::Utf16Le) {
                    u16::from_le_bytes([bytes[a], bytes[a + 1]])
                } else {
                    u16::from_be_bytes([bytes[a], bytes[a + 1]])
                };
                if (0xdc00..=0xdfff).contains(&unit) {
                    a += 2;
                }
            }
        }
        let mut b = (a + PAGE_BYTES).min(bytes.len());
        if base + (b as u64) < self.length {
            if matches!(self.encoding, Encoding::Utf8) {
                while b > a && bytes.get(b).is_some_and(|v| v & 0xc0 == 0x80) {
                    b -= 1;
                }
                if b > a && bytes[b - 1] == b'\r' && bytes.get(b) == Some(&b'\n') {
                    b -= 1;
                }
            } else {
                b &= !1;
                if b >= a + 2 {
                    let unit = if matches!(self.encoding, Encoding::Utf16Le) {
                        u16::from_le_bytes([bytes[b - 2], bytes[b - 1]])
                    } else {
                        u16::from_be_bytes([bytes[b - 2], bytes[b - 1]])
                    };
                    if (0xd800..=0xdbff).contains(&unit) || unit == 13 {
                        b -= 2;
                    }
                }
            }
        }
        let text = self.encoding.decode(&bytes[a..b])?;
        self.verify()?;
        check(token)?;
        let line_ending = if text.contains("\r\n") {
            "CRLF"
        } else if text.contains('\r') {
            "CR"
        } else {
            "LF"
        };
        self.window = Some(Window {
            start: base + a as u64,
            text: text.clone(),
        });
        self.syntax = None;
        Ok(LargePage {
            text,
            start: base + a as u64,
            end: base + b as u64,
            total_bytes: self.length,
            encoding: self.encoding,
            has_bom: !self.bom.is_empty(),
            line_ending,
            can_undo: !self.undo.is_empty(),
            can_redo: !self.redo.is_empty(),
            remaining_bytes: self.status().remaining_bytes,
            remaining_pieces: self.status().remaining_pieces,
        })
    }
    fn slice(&self, start: u64, end: u64) -> Vec<Piece> {
        let mut base = 0;
        let mut result = vec![];
        for p in &self.pieces {
            let a = base.max(start);
            let b = (base + p.len).min(end);
            if a < b {
                result.push(p.part(a - base, b - base));
            }
            base += p.len;
            if base >= end {
                break;
            }
        }
        result
    }
    fn splice(
        &mut self,
        start: u64,
        length: u64,
        inserted: &[Piece],
    ) -> Result<(), WorkspaceError> {
        if start > self.length || length > self.length - start {
            return Err(error("invalid_range", "编辑范围越界"));
        }
        let mut pieces = self.slice(0, start);
        pieces.extend_from_slice(inserted);
        pieces.extend(self.slice(start + length, self.length));
        if pieces.len() > MAX_PIECES {
            return Err(error("large_edit_budget", "分段编辑数量超出预算；请先保存"));
        }
        let added: u64 = inserted.iter().map(|p| p.len).sum();
        let new_length = (self.length - length)
            .checked_add(added)
            .filter(|v| *v <= i64::MAX as u64)
            .ok_or_else(|| error("invalid_range", "文件大小溢出"))?;
        let revision = self
            .revision
            .checked_add(1)
            .ok_or_else(|| error("revision_exhausted", "修订已达上限"))?;
        self.pieces = pieces;
        self.length = new_length;
        self.revision = revision;
        Ok(())
    }
    pub fn replace(
        &mut self,
        revision: u64,
        page: u64,
        range_start: usize,
        range_len: usize,
        text: &str,
    ) -> Result<(), WorkspaceError> {
        self.expect(revision)?;
        if text.len() > MAX_EDIT
            || text.contains('\0')
            || range_start.saturating_add(range_len) > 2 * MAX_EDIT
        {
            return Err(error(
                "large_edit_budget",
                "单次分段编辑限 1 MiB 且不能含空字符",
            ));
        }
        self.verify()?;
        if page > self.length {
            return Err(error("invalid_range", "片段位置越界"));
        }
        let window = self
            .window
            .as_ref()
            .filter(|w| w.start == page)
            .ok_or_else(|| error("stale_page", "当前片段已变化"))?;
        let (local_a, local_b) = utf8_range(&window.text, range_start, range_len)?;
        if window.text.len() - (local_b - local_a) + text.len() > MAX_EDIT {
            return Err(error(
                "large_edit_budget",
                "当前片段超过 1 MiB，请先切换片段",
            ));
        }
        let a: usize = window.text[..local_a]
            .chars()
            .map(|c| self.encoding.width(c))
            .sum();
        let b: usize = a + window.text[local_a..local_b]
            .chars()
            .map(|c| self.encoding.width(c))
            .sum::<usize>();
        let replacement = self.encoding.encode(text);
        let resident = self.owned_bytes();
        if resident + replacement.len() > MAX_RESIDENT {
            return Err(error(
                "large_edit_budget",
                "待提交编辑已达 64 MiB，请先保存再继续",
            ));
        }
        let inserted = if replacement.is_empty() {
            vec![]
        } else {
            vec![Piece {
                len: replacement.len() as u64,
                start: 0,
                backing: Backing::Insert(replacement.into()),
            }]
        };
        let start = page + a as u64;
        let removed = self.slice(start, page + b as u64);
        self.splice(start, (b - a) as u64, &inserted)?;
        self.undo.push(Edit {
            at: start,
            removed,
            inserted,
        });
        self.redo.clear();
        if let Some(window) = &mut self.window {
            window.text.replace_range(local_a..local_b, text);
        }
        self.syntax = None;
        while self.undo.len() > MAX_HISTORY
            || (self.undo.len() > 1
                && self
                    .undo
                    .iter()
                    .map(|e| e.inserted_len() + e.removed_len())
                    .sum::<u64>()
                    > MAX_HISTORY_BYTES)
        {
            self.undo.remove(0);
        }
        Ok(())
    }
    fn owned_bytes(&self) -> usize {
        let mut seen = HashSet::new();
        self.pieces
            .iter()
            .chain(
                self.undo
                    .iter()
                    .chain(&self.redo)
                    .flat_map(|e| e.removed.iter().chain(&e.inserted)),
            )
            .filter_map(|p| {
                if let Backing::Insert(data) = &p.backing
                    && seen.insert(data.as_ptr())
                {
                    return Some(data.len());
                }
                None
            })
            .sum()
    }
    fn history_file_bytes(&self) -> u64 {
        self.undo
            .iter()
            .chain(&self.redo)
            .flat_map(|e| e.removed.iter().chain(&e.inserted))
            .filter(|p| matches!(p.backing, Backing::File(_)))
            .map(|p| p.len)
            .sum()
    }
    pub fn status(&self) -> LargeStatus {
        LargeStatus {
            total_bytes: self.length,
            can_undo: !self.undo.is_empty(),
            can_redo: !self.redo.is_empty(),
            remaining_bytes: MAX_RESIDENT.saturating_sub(
                self.owned_bytes()
                    .saturating_add(self.history_file_bytes() as usize),
            ),
            remaining_pieces: MAX_PIECES.saturating_sub(self.pieces.len()),
        }
    }
    fn freeze_history(&mut self, token: Option<&HyCodeCancellation>) -> Result<(), WorkspaceError> {
        // Keep only the tiny deleted ranges needed for undo, never an entire
        // unlinked GB inode per save. Budget eviction occurs before committing
        // disk changes, and must never make a valid dirty buffer unsaveable.
        loop {
            let copied: u64 = self
                .undo
                .iter()
                .chain(&self.redo)
                .flat_map(|e| e.removed.iter().chain(&e.inserted))
                .filter(|p| matches!(p.backing, Backing::File(_)))
                .map(|p| p.len)
                .sum();
            if copied <= MAX_RESIDENT.saturating_sub(self.owned_bytes()) as u64 {
                break;
            }
            if !self.undo.is_empty() {
                self.undo.remove(0);
            } else if !self.redo.is_empty() {
                self.redo.remove(0);
            } else {
                break;
            }
        }
        for source in self.sources(true) {
            source.verify()?;
        }
        for edit in self.undo.iter_mut().chain(&mut self.redo) {
            for piece in edit.removed.iter_mut().chain(&mut edit.inserted) {
                check(token)?;
                if let Backing::File(source) = &piece.backing {
                    let mut bytes = vec![0; piece.len as usize];
                    read_exact(&source.file, &mut bytes, piece.start)?;
                    source.verify()?;
                    piece.backing = Backing::Insert(bytes.into());
                    piece.start = 0;
                }
            }
        }
        Ok(())
    }
    pub fn syntax(
        &mut self,
        revision: u64,
        path: &str,
        start: usize,
        end: usize,
    ) -> Result<crate::syntax::SyntaxSnapshot, WorkspaceError> {
        self.expect(revision)?;
        let window = self
            .window
            .as_ref()
            .ok_or_else(|| error("stale_page", "请先读取片段"))?;
        crate::syntax::snapshot(&mut self.syntax, &window.text, path, start, end)
    }
    pub fn find(
        &self,
        revision: u64,
        text: &str,
        from: u64,
        token: Option<&HyCodeCancellation>,
    ) -> Result<Option<u64>, WorkspaceError> {
        self.expect(revision)?;
        if text.is_empty() || text.len() > 4096 || text.contains('\0') {
            return Err(error("invalid_input", "查找文本须为 1–4096 字节的有效文本"));
        }
        let pattern = self.encoding.encode(text);
        self.verify()?;
        let mut start = from.min(self.length);
        while start < self.length {
            check(token)?;
            let count = (self.length - start).min((IO_CHUNK + pattern.len()) as u64) as usize;
            let bytes = self.read(start, count, token)?;
            // A linear-time prefix table keeps repeated-byte GB logs bounded.
            if let Some(found) = find_bytes(
                &bytes,
                &pattern,
                if matches!(self.encoding, Encoding::Utf8) {
                    1
                } else {
                    2
                },
                start,
            ) {
                self.verify()?;
                return Ok(Some(start + found as u64));
            }
            start += IO_CHUNK.min(count) as u64;
        }
        self.verify()?;
        check(token)?;
        Ok(None)
    }
    pub fn history(&mut self, revision: u64, redo: bool) -> Result<LargePage, WorkspaceError> {
        self.expect(revision)?;
        self.verify()?;
        let edit = (if redo {
            self.redo.last()
        } else {
            self.undo.last()
        })
        .cloned()
        .ok_or_else(|| error("empty_history", "没有可撤销的编辑"))?;
        let (length, insert) = if redo {
            (edit.removed_len(), &edit.inserted)
        } else {
            (edit.inserted_len(), &edit.removed)
        };
        for piece in insert {
            if let Backing::File(source) = &piece.backing {
                source.verify()?;
            }
        }
        let mut candidate = Self {
            pieces: self.pieces.clone(),
            length: self.length,
            encoding: self.encoding,
            bom: self.bom.clone(),
            revision: self.revision,
            undo: vec![],
            redo: vec![],
            window: None,
            syntax: None,
        };
        candidate.splice(edit.at, length, insert)?;
        let focus = self
            .window
            .as_ref()
            .filter(|w| {
                edit.at >= w.start && edit.at < w.start + self.encoding.encode(&w.text).len() as u64
            })
            .map_or(edit.at, |w| w.start);
        // All I/O/decoding that could fail happens before history/revision or
        // native projection changes. The committed page is returned directly.
        let mut page = candidate.page(candidate.revision, focus, None)?;
        self.pieces = candidate.pieces;
        self.length = candidate.length;
        self.revision = candidate.revision;
        self.window = candidate.window;
        self.syntax = None;
        if redo {
            self.redo.pop();
            self.undo.push(edit);
        } else {
            self.undo.pop();
            self.redo.push(edit);
        }
        let status = self.status();
        page.can_undo = status.can_undo;
        page.can_redo = status.can_redo;
        page.remaining_bytes = status.remaining_bytes;
        page.remaining_pieces = status.remaining_pieces;
        Ok(page)
    }
    pub fn export(
        &mut self,
        revision: u64,
        fd: i32,
        token: Option<&HyCodeCancellation>,
    ) -> Result<(), WorkspaceError> {
        self.expect(revision)?;
        check(token)?;
        self.verify()?;
        let destination = File::from(
            unsafe { BorrowedFd::borrow_raw(fd) }
                .try_clone_to_owned()
                .map_err(io)?,
        );
        let info = destination.metadata().map_err(io)?;
        if !info.is_file()
            || info.nlink() != 1
            || self.sources(true).iter().any(|s| {
                s.file
                    .metadata()
                    .is_ok_and(|m| m.dev() == info.dev() && m.ino() == info.ino())
            })
        {
            return Err(error("invalid_output", "导出只能写入独立的临时普通文件"));
        }
        self.freeze_history(token)?;
        destination.set_len(0).map_err(io)?;
        destination.write_all_at(&self.bom, 0).map_err(io)?;
        let mut output = self.bom.len() as u64;
        let mut buffer = vec![0; IO_CHUNK];
        for piece in &self.pieces {
            let mut position = 0;
            while position < piece.len {
                check(token)?;
                let count = (piece.len - position).min(IO_CHUNK as u64) as usize;
                let bytes = match &piece.backing {
                    Backing::File(s) => {
                        read_exact(&s.file, &mut buffer[..count], piece.start + position)?;
                        &buffer[..count]
                    }
                    Backing::Insert(data) => {
                        &data[(piece.start + position) as usize
                            ..(piece.start + position) as usize + count]
                    }
                };
                destination.write_all_at(bytes, output).map_err(io)?;
                output += count as u64;
                position += count as u64;
            }
        }
        self.verify()?;
        check(token)
    }
    pub fn saved(&mut self, revision: u64, fd: i32) -> Result<(), WorkspaceError> {
        self.expect(revision)?;
        let file = File::from(
            unsafe { BorrowedFd::borrow_raw(fd) }
                .try_clone_to_owned()
                .map_err(io)?,
        );
        let source = Source::new(file)?;
        if source.file.metadata().map_err(io)?.len() != self.length + self.bom.len() as u64 {
            return Err(error("invalid_output", "保存长度不匹配"));
        }
        self.pieces = if self.length == 0 {
            vec![]
        } else {
            vec![Piece {
                backing: Backing::File(source),
                start: self.bom.len() as u64,
                len: self.length,
            }]
        };
        Ok(())
    }
    pub fn markup(
        &self,
        revision: u64,
        markdown: bool,
        token: Option<&HyCodeCancellation>,
    ) -> Result<crate::markup::MarkupContent, WorkspaceError> {
        self.expect(revision)?;
        if self.length > crate::markup::MAX_SOURCE as u64 {
            return Err(error(
                "markup_preview",
                "此大文件超过整页预览预算，请使用分段源码编辑",
            ));
        }
        self.verify()?;
        let bytes = self.read(0, self.length as usize, token)?;
        let text = self.encoding.decode(&bytes)?;
        self.verify()?;
        check(token)?;
        crate::markup::render_cancellable(&text, markdown, token)
    }
}
fn read_exact(file: &File, mut buffer: &mut [u8], mut position: u64) -> Result<(), WorkspaceError> {
    while !buffer.is_empty() {
        match file.read_at(buffer, position) {
            Ok(0) => return Err(error("external_change", "文件在读取期间缩短")),
            Ok(n) => {
                position += n as u64;
                buffer = &mut buffer[n..];
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) => return Err(io(e)),
        }
    }
    Ok(())
}

fn utf8_range(text: &str, start: usize, length: usize) -> Result<(usize, usize), WorkspaceError> {
    let end = start
        .checked_add(length)
        .ok_or_else(|| error("invalid_range", "编辑范围溢出"))?;
    let mut units = 0;
    let mut a = None;
    for (byte, c) in text
        .char_indices()
        .chain(std::iter::once((text.len(), '\0')))
    {
        if units == start {
            a = Some(byte);
        }
        if units == end {
            return a
                .map(|a| (a, byte))
                .ok_or_else(|| error("invalid_range", "编辑切分 Unicode"));
        }
        units += c.len_utf16();
        if units > end {
            break;
        }
    }
    Err(error("invalid_range", "编辑越界或切分 Unicode"))
}
fn find_bytes(bytes: &[u8], pattern: &[u8], alignment: u64, offset: u64) -> Option<usize> {
    let mut prefix = vec![0; pattern.len()];
    let mut j = 0;
    for i in 1..pattern.len() {
        while j > 0 && pattern[i] != pattern[j] {
            j = prefix[j - 1];
        }
        if pattern[i] == pattern[j] {
            j += 1;
        }
        prefix[i] = j;
    }
    j = 0;
    for (i, b) in bytes.iter().enumerate() {
        while j > 0 && *b != pattern[j] {
            j = prefix[j - 1];
        }
        if *b == pattern[j] {
            j += 1;
        }
        if j == pattern.len() {
            let start = i + 1 - pattern.len();
            if (offset + start as u64).is_multiple_of(alignment) {
                return Some(start);
            }
            j = prefix[j - 1];
        }
    }
    None
}

#[cfg(test)]
#[path = "large_document_tests.rs"]
mod tests;
