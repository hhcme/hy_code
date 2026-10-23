use crate::document::TextDocument;
use crate::{HyCodeBuffer, WorkspaceError};
use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    ptr, slice,
};

#[repr(C)]
pub struct HyCodeTextResult {
    pub value: HyCodeBuffer,
    pub error: HyCodeBuffer,
    pub revision: u64,
}

fn buffer(bytes: Vec<u8>) -> HyCodeBuffer {
    if bytes.is_empty() {
        return empty();
    }
    let mut bytes = bytes.into_boxed_slice();
    let result = HyCodeBuffer {
        data: bytes.as_mut_ptr(),
        len: bytes.len(),
    };
    std::mem::forget(bytes);
    result
}
fn empty() -> HyCodeBuffer {
    HyCodeBuffer {
        data: ptr::null_mut(),
        len: 0,
    }
}
fn reply(result: Result<(Vec<u8>, u64), WorkspaceError>) -> HyCodeTextResult {
    match result {
        Ok((bytes, revision)) => HyCodeTextResult {
            value: buffer(bytes),
            error: empty(),
            revision,
        },
        Err(error) => HyCodeTextResult {
            value: empty(),
            error: buffer(serde_json::to_vec(&error).unwrap_or_default()),
            revision: 0,
        },
    }
}
pub(crate) fn guarded(
    body: impl FnOnce() -> Result<(Vec<u8>, u64), WorkspaceError>,
) -> HyCodeTextResult {
    reply(catch_unwind(AssertUnwindSafe(body)).unwrap_or_else(|_| {
        Err(WorkspaceError::new(
            "internal_error",
            "文本内核发生内部错误",
        ))
    }))
}
unsafe fn bytes<'a>(data: *const u8, len: usize) -> Result<&'a [u8], WorkspaceError> {
    if len == 0 {
        return Ok(&[]);
    }
    if data.is_null() || len > crate::document::MAX_TEXT_BYTES {
        return Err(WorkspaceError::new("invalid_input", "文本参数无效或过长"));
    }
    Ok(unsafe { slice::from_raw_parts(data, len) })
}

/// # Safety
/// Borrow valid UTF-8 <=256 KiB for this synchronous background call. No
/// retained pointers, I/O, database connections, callbacks or text mutations.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_sql_analyze(
    data: *const u8,
    len: usize,
    dialect: u32,
    formatting: bool,
) -> HyCodeTextResult {
    guarded(|| {
        if len > 256 * 1024 {
            return Err(WorkspaceError::new("sql_budget", "SQL 超过 256 KiB"));
        }
        let text = std::str::from_utf8(unsafe { bytes(data, len) }?)
            .map_err(|_| WorkspaceError::new("invalid_utf8", "SQL 不是 UTF-8"))?;
        let result = crate::sql::analyze(text, dialect, formatting)?;
        Ok((
            serde_json::to_vec(&result)
                .map_err(|_| WorkspaceError::new("encoding_failed", "SQL 响应编码失败"))?,
            0,
        ))
    })
}
/// # Safety
/// `output` must be writable; bytes must remain readable for this call.
/// A successful output is exclusively owned by the caller until document_free.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_open(
    data: *const u8,
    len: usize,
    output: *mut *mut TextDocument,
) -> HyCodeTextResult {
    guarded(|| {
        let output = unsafe { output.as_mut() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档输出为空"))?;
        *output = ptr::null_mut();
        let document = TextDocument::open(unsafe { bytes(data, len) }?)?;
        let snapshot = serde_json::to_vec(&document.snapshot())
            .map_err(|_| WorkspaceError::new("encoding_failed", "文本响应编码失败"))?;
        *output = Box::into_raw(Box::new(document));
        Ok((snapshot, 0))
    })
}
/// # Safety
/// Live document, exclusive serial access. UTF-16 ranges must be scalar boundaries.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_replace(
    document: *mut TextDocument,
    expected: u64,
    start: usize,
    length: usize,
    data: *const u8,
    len: usize,
) -> HyCodeTextResult {
    guarded(|| {
        let document = unsafe { document.as_mut() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档为空"))?;
        let text = std::str::from_utf8(unsafe { bytes(data, len) }?)
            .map_err(|_| WorkspaceError::new("invalid_utf8", "编辑增量不是 UTF-8"))?;
        document.replace(expected, start, length, text)?;
        Ok((Vec::new(), document.revision()))
    })
}
/// # Safety
/// Same document/owned-buffer rules, optional live token through return.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_markup_cancellable(
    document: *const TextDocument,
    expected: u64,
    markdown: bool,
    token: *const crate::HyCodeCancellation,
) -> HyCodeTextResult {
    guarded(|| {
        let document = unsafe { document.as_ref() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档为空"))?;
        let value = document.markup_cancellable(expected, markdown, unsafe { token.as_ref() })?;
        Ok((
            serde_json::to_vec(&value)
                .map_err(|_| WorkspaceError::new("encoding_failed", "预览响应编码失败"))?,
            document.revision(),
        ))
    })
}
/// # Safety
/// Live document, exclusive serial access. Value contains raw original-encoding bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_bytes(
    document: *const TextDocument,
    expected: u64,
) -> HyCodeTextResult {
    guarded(|| {
        let document = unsafe { document.as_ref() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档为空"))?;
        Ok((document.bytes(expected)?, document.revision()))
    })
}
/// # Safety
/// Live document, serialized background access. Returns immutable revision-bound
/// HTML/source-map JSON, never mutates text, reads files or executes content.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_markup(
    document: *const TextDocument,
    expected: u64,
    markdown: bool,
) -> HyCodeTextResult {
    guarded(|| {
        let document = unsafe { document.as_ref() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档为空"))?;
        let value = document.markup(expected, markdown)?;
        let data = serde_json::to_vec(&value)
            .map_err(|_| WorkspaceError::new("encoding_failed", "预览响应编码失败"))?;
        Ok((data, document.revision()))
    })
}
/// # Safety
/// Live document with exclusive serial access; path bytes remain readable for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_syntax(
    document: *mut TextDocument,
    expected: u64,
    path: *const u8,
    path_len: usize,
    start: usize,
    end: usize,
) -> HyCodeTextResult {
    guarded(|| {
        let document = unsafe { document.as_mut() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档为空"))?;
        if path_len > 16_384 {
            return Err(WorkspaceError::new("invalid_input", "文件名过长"));
        }
        let path = std::str::from_utf8(unsafe { bytes(path, path_len) }?)
            .map_err(|_| WorkspaceError::new("invalid_utf8", "文件名不是 UTF-8"))?;
        let snapshot = document.syntax(expected, path, start, end)?;
        let json = serde_json::to_vec(&snapshot)
            .map_err(|_| WorkspaceError::new("encoding_failed", "高亮编码失败"))?;
        Ok((json, document.revision()))
    })
}
/// # Safety
/// Live document with exclusive serial background access. Does not edit text or
/// change revision. JSON boolean reports whether a parser cache was removed.
/// Optional cancellation token stays live through return, checked at commit.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_trim_cache(
    document: *mut TextDocument,
    token: *const crate::HyCodeCancellation,
) -> HyCodeTextResult {
    guarded(|| {
        let document = unsafe { document.as_mut() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "文档为空"))?;
        if unsafe { token.as_ref() }.is_some_and(crate::HyCodeCancellation::is_cancelled) {
            return Err(WorkspaceError::new("cancelled", "缓存清理已取消"));
        }
        Ok((
            if document.trim_cache() {
                b"true".to_vec()
            } else {
                b"false".to_vec()
            },
            document.revision(),
        ))
    })
}

/// # Safety
/// Thread-safe background eviction. Borrow UTF-8 path <=16KiB and optional live
/// token through return. JSON counts unused grammars, not bytes freed. Active
/// parsers and the given path's fragment/embedded-language queries survive.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_syntax_trim_cache(
    path: *const u8,
    path_len: usize,
    token: *const crate::HyCodeCancellation,
) -> HyCodeTextResult {
    guarded(|| {
        if path_len > 16_384 {
            return Err(WorkspaceError::new("invalid_input", "文件名过长"));
        }
        let path = std::str::from_utf8(unsafe { bytes(path, path_len) }?)
            .map_err(|_| WorkspaceError::new("invalid_utf8", "文件名不是 UTF-8"))?;
        Ok((
            crate::syntax_language::trim_cache(path, unsafe { token.as_ref() })?
                .to_string()
                .into_bytes(),
            0,
        ))
    })
}

/// # Safety
/// Exactly once for an owned document, after all operations have completed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_free(document: *mut TextDocument) {
    if !document.is_null() {
        drop(unsafe { Box::from_raw(document) });
    }
}

/// # Safety
/// Immutable UTF-8 projection <=262144 bytes /65536 UTF-16 units and UTF-8 path
/// <=16KiB are borrowed only for this background call. No document/FD access or
/// edits. Owned syntax JSON, start shifts spans into the native page. Same free
/// and panic rules as other text results. One host worker serializes requests.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_syntax_fragment(
    data: *const u8,
    len: usize,
    path: *const u8,
    path_len: usize,
    start: usize,
) -> HyCodeTextResult {
    guarded(|| {
        if len > 262_144 || path_len > 16_384 {
            return Err(WorkspaceError::new("invalid_input", "高亮片段过大"));
        }
        let text = std::str::from_utf8(unsafe { bytes(data, len) }?)
            .map_err(|_| WorkspaceError::new("invalid_utf8", "片段不是 UTF-8"))?;
        let path = std::str::from_utf8(unsafe { bytes(path, path_len) }?)
            .map_err(|_| WorkspaceError::new("invalid_utf8", "路径不是 UTF-8"))?;
        let length = text.encode_utf16().count();
        if length > 65_536 || start.checked_add(length).is_none() {
            return Err(WorkspaceError::new("invalid_range", "高亮片段范围无效"));
        }
        let mut result = crate::syntax::snapshot(&mut None, text, path, 0, length)?;
        result.start = start;
        if result.status == "ready" {
            result.status = "windowed";
        }
        for span in &mut result.spans {
            span.start += start;
        }
        Ok((
            serde_json::to_vec(&result)
                .map_err(|_| WorkspaceError::new("encoding_failed", "高亮响应编码失败"))?,
            0,
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hycode_buffer_free;
    #[test]
    fn cache_api_rejects_null_handles_and_keeps_live_revisions() {
        unsafe {
            let invalid = hycode_text_trim_cache(ptr::null_mut(), ptr::null());
            assert!(!invalid.error.data.is_null());
            hycode_buffer_free(invalid.value);
            hycode_buffer_free(invalid.error);
            let mut document = ptr::null_mut();
            let opened = hycode_text_open(b"abc".as_ptr(), 3, &mut document);
            hycode_buffer_free(opened.value);
            hycode_buffer_free(opened.error);
            let trimmed = hycode_text_trim_cache(document, ptr::null());
            assert!(trimmed.error.data.is_null());
            assert_eq!(trimmed.revision, 0);
            assert_eq!(
                slice::from_raw_parts(trimmed.value.data, trimmed.value.len),
                b"false"
            );
            hycode_buffer_free(trimmed.value);
            hycode_buffer_free(trimmed.error);
            (*document).syntax(0, "main.dart", 0, 3).unwrap();
            let token = crate::hycode_cancel_new();
            crate::hycode_cancel(token);
            let cancelled = hycode_text_trim_cache(document, token);
            assert!(!cancelled.error.data.is_null());
            hycode_buffer_free(cancelled.value);
            hycode_buffer_free(cancelled.error);
            let shared_cancelled = hycode_syntax_trim_cache(ptr::null(), 0, token);
            assert!(!shared_cancelled.error.data.is_null());
            hycode_buffer_free(shared_cancelled.value);
            hycode_buffer_free(shared_cancelled.error);
            crate::hycode_cancel_free(token);
            // A cancelled ABI call left the live document cache untouched.
            assert!((*document).trim_cache());
            hycode_text_free(document);
            let shared = hycode_syntax_trim_cache(ptr::null(), 0, ptr::null());
            assert!(shared.error.data.is_null());
            hycode_buffer_free(shared.value);
            hycode_buffer_free(shared.error);
        }
    }
    #[test]
    fn owned_handles_and_both_result_buffers_cover_success_and_errors() {
        unsafe {
            let mut document = ptr::null_mut();
            let opened = hycode_text_open(b"abc".as_ptr(), 3, &mut document);
            assert!(!document.is_null());
            assert!(opened.error.data.is_null());
            hycode_buffer_free(opened.value);
            hycode_buffer_free(opened.error);
            let edited = hycode_text_replace(document, 0, 1, 1, "中".as_ptr(), 3);
            assert_eq!(edited.revision, 1);
            hycode_buffer_free(edited.value);
            hycode_buffer_free(edited.error);
            let stale = hycode_text_bytes(document, 0);
            assert!(!stale.error.data.is_null());
            hycode_buffer_free(stale.value);
            hycode_buffer_free(stale.error);
            let bytes = hycode_text_bytes(document, 1);
            assert_eq!(
                slice::from_raw_parts(bytes.value.data, bytes.value.len),
                "a中c".as_bytes()
            );
            hycode_buffer_free(bytes.value);
            hycode_buffer_free(bytes.error);
            hycode_text_free(document);
            hycode_text_free(ptr::null_mut());
            let bad = hycode_text_open(ptr::null(), 1, &mut document);
            assert!(document.is_null());
            assert!(!bad.error.data.is_null());
            hycode_buffer_free(bad.value);
            hycode_buffer_free(bad.error);
        }
    }
}
