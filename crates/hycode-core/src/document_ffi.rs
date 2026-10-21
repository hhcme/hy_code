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
fn guarded(body: impl FnOnce() -> Result<(Vec<u8>, u64), WorkspaceError>) -> HyCodeTextResult {
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
/// Exactly once for an owned document, after all operations have completed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_text_free(document: *mut TextDocument) {
    if !document.is_null() {
        drop(unsafe { Box::from_raw(document) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hycode_buffer_free;
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
