use super::*;
use std::{
    io::Write,
    os::fd::AsRawFd,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static ID: AtomicU64 = AtomicU64::new(0);
struct Fixture {
    root: PathBuf,
    file: File,
}
impl Fixture {
    fn new(bytes: &[u8]) -> Self {
        let root = std::env::temp_dir().join(format!(
            "hycode-large-rust-{}-{}",
            std::process::id(),
            ID.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&root).unwrap();
        let mut file = File::options()
            .create_new(true)
            .read(true)
            .write(true)
            .open(root.join("source"))
            .unwrap();
        file.write_all(bytes).unwrap();
        Self { root, file }
    }
    fn doc(&self) -> LargeDocument {
        unsafe { LargeDocument::open(self.file.as_raw_fd()) }.unwrap()
    }
    fn output(&self) -> File {
        File::options()
            .create(true)
            .truncate(true)
            .read(true)
            .write(true)
            .open(self.root.join("output"))
            .unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}
#[test]
fn page_boundaries_and_tiny_edits_are_lossless_against_unicode_model() {
    let original = "a😀中文\r\n".repeat(32_000);
    let f = Fixture::new(original.as_bytes());
    let mut doc = f.doc();
    let mut model = original.clone();
    let mut at = 0;
    let mut joined = String::new();
    while at < doc.length {
        let page = doc.page(0, at, None).unwrap();
        assert_eq!(page.start, at);
        assert!(page.end > at);
        joined += &page.text;
        at = page.end;
    }
    assert_eq!(joined, original);
    for n in 0..120 {
        let page = doc.page(n, 0, None).unwrap();
        let position = (n as usize * 13) % 2_000;
        let byte = page.text.char_indices().nth(position).unwrap().0;
        let units = page.text[..byte].encode_utf16().count();
        let size = page.text[byte..].chars().next().unwrap().len_utf16();
        let replacement = if n % 2 == 0 { "🦀中" } else { "Q\r\n" };
        doc.replace(n, 0, units, size, replacement).unwrap();
        let end = byte + model[byte..].chars().next().unwrap().len_utf8();
        model.replace_range(byte..end, replacement);
    }
    let output = f.output();
    doc.export(120, output.as_raw_fd(), None).unwrap();
    assert_eq!(
        std::fs::read(f.root.join("output")).unwrap(),
        model.as_bytes()
    );
    let revision = doc.revision;
    assert!(doc.replace(0, 0, 0, 1, "bad").is_err());
    assert_eq!(doc.revision, revision);
}
#[test]
fn logical_file_above_four_gib_uses_u64_offsets_and_bounded_pages() {
    // Piece-table test: >4GiB of valid logical text references one 128KiB file.
    // Does not create a fake sparse binary or write GBs during normal tests.
    let f = Fixture::new(&vec![b'x'; PAGE_BYTES * 2]);
    let mut doc = f.doc();
    let template = doc.pieces[0].clone();
    doc.pieces = vec![template; 32_769];
    doc.length = doc.pieces.iter().map(|p| p.len).sum();
    // The last page begins above the 32-bit byte-offset boundary.
    assert!(doc.length > u32::MAX as u64);
    let page = doc.page(0, doc.length - PAGE_BYTES as u64, None).unwrap();
    assert!(page.start > u32::MAX as u64);
    assert_eq!(page.text.len(), PAGE_BYTES);
    assert_eq!(page.end, doc.length);
    assert!(doc.window.as_ref().unwrap().text.len() <= PAGE_BYTES);
}
#[test]
fn cancellation_stale_pages_and_invalid_unicode_never_mutate_the_table() {
    let f = Fixture::new("😀".repeat(20_000).as_bytes());
    let mut doc = f.doc();
    doc.page(0, 0, None).unwrap();
    assert!(doc.replace(0, 0, 1, 1, "bad").is_err());
    assert!(doc.replace(0, 12, 0, 0, "bad").is_err());
    assert_eq!(doc.revision, 0);
    let token = crate::hycode_cancel_new();
    unsafe {
        crate::hycode_cancel(token);
    }
    assert_eq!(
        doc.page(0, 40_000, unsafe { token.as_ref() })
            .err()
            .unwrap()
            .code,
        "cancelled"
    );
    assert_eq!(doc.window.as_ref().unwrap().start, 0);
    let output = f.output();
    assert_eq!(
        doc.export(0, output.as_raw_fd(), unsafe { token.as_ref() })
            .unwrap_err()
            .code,
        "cancelled"
    );
    assert_eq!(output.metadata().unwrap().len(), 0);
    assert!(doc.export(0, f.file.as_raw_fd(), None).is_err());
    unsafe {
        crate::hycode_cancel_free(token);
    }
}
#[test]
fn reads_detect_external_truncation_without_mapping_or_losing_edits() {
    let f = Fixture::new(&vec![b'a'; PAGE_BYTES * 2]);
    let mut doc = f.doc();
    doc.page(0, 0, None).unwrap();
    doc.replace(0, 0, 0, 1, "x").unwrap();
    f.file.set_len(4).unwrap();
    assert_eq!(doc.page(1, 0, None).err().unwrap().code, "external_change");
    assert_eq!(doc.undo.len(), 1);
    let output = f.output();
    assert_eq!(
        doc.export(1, output.as_raw_fd(), None).unwrap_err().code,
        "external_change"
    );
    assert_eq!(output.metadata().unwrap().len(), 0);
}
#[test]
fn utf16_stream_search_is_aligned_and_respects_overlap() {
    let source = "a".repeat(IO_CHUNK / 2 - 1) + "😀NEEDLE";
    for little in [true, false] {
        let mut bytes = if little {
            vec![0xff, 0xfe]
        } else {
            vec![0xfe, 0xff]
        };
        for unit in source.encode_utf16() {
            bytes.extend(if little {
                unit.to_le_bytes()
            } else {
                unit.to_be_bytes()
            });
        }
        let f = Fixture::new(&bytes);
        let doc = f.doc();
        assert_eq!(
            doc.find(0, "😀NEEDLE", 0, None).unwrap(),
            Some(IO_CHUNK as u64 - 2)
        );
        assert_eq!(doc.find(0, "missing", 0, None).unwrap(), None);
    }
}
#[test]
fn failed_history_page_does_not_change_revision_history_or_active_projection() {
    let mut bytes = vec![b'a'; 180_000];
    bytes[70_000] = 0xff;
    let f = Fixture::new(&bytes);
    let mut doc = f.doc();
    doc.page(0, 0, None).unwrap();
    doc.replace(0, 0, 65_000, 1, "x").unwrap();
    // Staying within the old validated page succeeds transactionally.
    let page = doc.history(1, false).unwrap();
    assert_eq!(page.start, 0);
    doc.replace(2, 0, 65_000, 1, "x").unwrap();
    // A different current page forces the undo's target to load past bad bytes.
    doc.page(3, 100_000, None).unwrap();
    assert_eq!(
        doc.history(3, false).err().unwrap().code,
        "invalid_encoding"
    );
    assert_eq!(doc.revision, 3);
    assert_eq!(doc.window.as_ref().unwrap().start, 100_000);
    doc.replace(3, 100_000, 0, 1, "z").unwrap();
}
#[test]
fn repeated_save_freezes_only_undo_ranges_and_releases_all_old_inode_sources() {
    let f = Fixture::new(&vec![b'a'; 180_000]);
    let mut doc = f.doc();
    for revision in 0..6 {
        doc.page(revision, 0, None).unwrap();
        doc.replace(revision, 0, 0, 1, if revision % 2 == 0 { "x" } else { "y" })
            .unwrap();
        let file = f.output();
        doc.export(revision + 1, file.as_raw_fd(), None).unwrap();
        assert!(
            doc.undo
                .iter()
                .flat_map(|e| &e.removed)
                .all(|p| matches!(p.backing, Backing::Insert(_)))
        );
        std::fs::rename(f.root.join("output"), f.root.join("source")).unwrap();
        doc.saved(revision + 1, file.as_raw_fd()).unwrap();
        assert_eq!(doc.sources(true).len(), 1);
        assert!(doc.sources(true)[0].file.metadata().unwrap().nlink() > 0);
        assert!(doc.owned_bytes() < 128);
    }
    doc.history(6, false).unwrap();
    let file = f.output();
    doc.export(7, file.as_raw_fd(), None).unwrap();
    assert_eq!(std::fs::read(f.root.join("output")).unwrap()[0], b'x');
}
