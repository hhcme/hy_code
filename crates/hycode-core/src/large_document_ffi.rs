use crate::{
    HyCodeCancellation, HyCodeTextResult, WorkspaceError, document_ffi::guarded,
    large_document::LargeDocument,
};
use std::{ptr, slice};
fn encode(value: &impl serde::Serialize, revision: u64) -> Result<(Vec<u8>, u64), WorkspaceError> {
    Ok((
        serde_json::to_vec(value)
            .map_err(|_| WorkspaceError::new("encoding_failed", "大文件响应编码失败"))?,
        revision,
    ))
}
unsafe fn document<'a>(doc: *mut LargeDocument) -> Result<&'a mut LargeDocument, WorkspaceError> {
    unsafe { doc.as_mut() }.ok_or_else(|| WorkspaceError::new("invalid_input", "大文件文档为空"))
}
unsafe fn text<'a>(data: *const u8, len: usize, max: usize) -> Result<&'a str, WorkspaceError> {
    if len > max || (len > 0 && data.is_null()) {
        return Err(WorkspaceError::new("invalid_input", "文本参数无效"));
    }
    let bytes = if len == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(data, len) }
    };
    std::str::from_utf8(bytes).map_err(|_| WorkspaceError::new("invalid_utf8", "文本不是 UTF-8"))
}
/// # Safety
/// Lend a valid authorized regular-file fd for this call; Rust duplicates it.
/// Output must be writable. All returned buffers and the handle are owned.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_open(
    fd: i32,
    output: *mut *mut LargeDocument,
) -> HyCodeTextResult {
    guarded(|| {
        let output = unsafe { output.as_mut() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档输出为空"))?;
        *output = ptr::null_mut();
        let doc = unsafe { LargeDocument::open(fd) }?;
        let result = encode(&doc.status(), 0)?;
        *output = Box::into_raw(Box::new(doc));
        Ok(result)
    })
}
/// # Safety
/// Live serial background handle; optional live cancellation token until return.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_page(
    doc: *mut LargeDocument,
    revision: u64,
    start: u64,
    token: *const HyCodeCancellation,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        encode(
            &doc.page(revision, start, unsafe { token.as_ref() })?,
            doc.revision(),
        )
    })
}
/// # Safety
/// Live serial background handle. Returns only bounded budget/history metadata.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_status(doc: *mut LargeDocument) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        encode(&doc.status(), doc.revision())
    })
}
/// # Safety
/// Live serial handle, UTF-16 range within its most recent page, borrowed UTF-8
/// <=1 MiB. Reject old revisions/pages. Owned JSON status, never full text.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_replace(
    doc: *mut LargeDocument,
    revision: u64,
    page: u64,
    start: usize,
    length: usize,
    data: *const u8,
    len: usize,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        doc.replace(revision, page, start, length, unsafe {
            text(data, len, 1024 * 1024)
        }?)?;
        encode(&doc.status(), doc.revision())
    })
}
/// # Safety
/// Live serial handle. Undo history belongs only to Rust. JSON byte focus.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_history(
    doc: *mut LargeDocument,
    revision: u64,
    redo: bool,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        let page = doc.history(revision, redo)?;
        encode(&page, doc.revision())
    })
}
/// # Safety
/// Live serial handle, borrowed UTF-8 path <=16KiB, page-relative scalar UTF-16
/// bounds <=65536 units. Parser sees only the bounded current page.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_syntax(
    doc: *mut LargeDocument,
    revision: u64,
    path: *const u8,
    len: usize,
    start: usize,
    end: usize,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        encode(
            &doc.syntax(revision, unsafe { text(path, len, 16384) }?, start, end)?,
            doc.revision(),
        )
    })
}
/// # Safety
/// Live serial handle, borrowed search UTF-8 <=4096 bytes, live optional token.
/// Streaming literal search; JSON null or byte offset, never an unbounded list.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_find(
    doc: *mut LargeDocument,
    revision: u64,
    data: *const u8,
    len: usize,
    from: u64,
    token: *const HyCodeCancellation,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        encode(
            &doc.find(revision, unsafe { text(data, len, 4096) }?, from, unsafe {
                token.as_ref()
            })?,
            doc.revision(),
        )
    })
}
/// # Safety
/// Live serial handle, lend an independent writable temporary regular fd (not a
/// backing file), optional live token. Streaming original encoding including BOM.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_export(
    doc: *mut LargeDocument,
    revision: u64,
    fd: i32,
    token: *const HyCodeCancellation,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        doc.export(revision, fd, unsafe { token.as_ref() })?;
        Ok((vec![], doc.revision()))
    })
}
/// # Safety
/// Host has atomically installed the exported temp fd for this exact revision.
/// Lend its readable fd, after the rename commit point.
/// Export froze bounded undo fragments; rebase releases old complete-file fds.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_saved(
    doc: *mut LargeDocument,
    revision: u64,
    fd: i32,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        doc.saved(revision, fd)?;
        Ok((vec![], doc.revision()))
    })
}
/// # Safety
/// Live serialized document and optional live token. Complete static preview is
/// bounded separately from disk-backed editing; no page is mistaken for a file.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_markup(
    doc: *mut LargeDocument,
    revision: u64,
    markdown: bool,
    token: *const HyCodeCancellation,
) -> HyCodeTextResult {
    guarded(|| {
        let doc = unsafe { document(doc) }?;
        encode(
            &doc.markup(revision, markdown, unsafe { token.as_ref() })?,
            doc.revision(),
        )
    })
}
/// # Safety
/// Owned handle exactly once, after every borrower and in-flight operation.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_large_free(doc: *mut LargeDocument) {
    if !doc.is_null() {
        drop(unsafe { Box::from_raw(doc) });
    }
}
