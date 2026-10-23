use crate::directory::{DirectorySnapshot, WorkspaceError, list_directory};
use serde::Serialize;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::ptr;
use std::slice;
use std::sync::atomic::{AtomicBool, Ordering};

#[repr(C)]
pub struct HyCodeBuffer {
    pub data: *mut u8,
    pub len: usize,
}

pub struct HyCodeCancellation {
    cancelled: AtomicBool,
}

impl HyCodeCancellation {
    pub(crate) fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }
}

#[derive(Serialize)]
struct Response {
    snapshot: Option<DirectorySnapshot>,
    error: Option<WorkspaceError>,
}

#[unsafe(no_mangle)]
pub extern "C" fn hycode_core_abi_version() -> u32 {
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn hycode_cancel_new() -> *mut HyCodeCancellation {
    Box::into_raw(Box::new(HyCodeCancellation {
        cancelled: AtomicBool::new(false),
    }))
}

/// # Safety
/// `token` must remain alive until every call borrowing it has returned.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_cancel(token: *const HyCodeCancellation) {
    if let Some(token) = unsafe { token.as_ref() } {
        token.cancelled.store(true, Ordering::Relaxed);
    }
}

/// # Safety
/// Free exactly once, after all concurrent list/cancel calls have completed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_cancel_free(token: *mut HyCodeCancellation) {
    if !token.is_null() {
        drop(unsafe { Box::from_raw(token) });
    }
}

unsafe fn input_string<'a>(data: *const u8, len: usize) -> Result<&'a str, WorkspaceError> {
    if len == 0 {
        return Ok("");
    }
    if data.is_null() || len > 16_384 {
        return Err(WorkspaceError::new("invalid_input", "路径参数无效或过长"));
    }
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    std::str::from_utf8(bytes)
        .map_err(|_| WorkspaceError::new("invalid_utf8", "路径不是有效的 UTF-8"))
}

/// # Safety
/// Non-null byte pointers must reference `len` readable bytes for the duration of the call.
/// `token` must be a live token returned by `hycode_cancel_new` and may be cancelled concurrently.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_core_list(
    root: *const u8,
    root_len: usize,
    relative: *const u8,
    relative_len: usize,
    include_hidden: bool,
    token: *const HyCodeCancellation,
) -> HyCodeBuffer {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let root = unsafe { input_string(root, root_len) }?;
        let relative = unsafe { input_string(relative, relative_len) }?;
        if root.is_empty() {
            return Err(WorkspaceError::new("invalid_input", "项目路径为空"));
        }
        let token = unsafe { token.as_ref() }
            .ok_or_else(|| WorkspaceError::new("invalid_input", "取消令牌为空"))?;
        list_directory(
            Path::new(root),
            Path::new(relative),
            include_hidden,
            &token.cancelled,
        )
    }))
    .unwrap_or_else(|_| {
        Err(WorkspaceError::new(
            "internal_error",
            "目录读取发生内部错误",
        ))
    });
    let response = match result {
        Ok(snapshot) => Response {
            snapshot: Some(snapshot),
            error: None,
        },
        Err(error) => Response {
            snapshot: None,
            error: Some(error),
        },
    };
    match serde_json::to_vec(&response) {
        Ok(bytes) => {
            let mut bytes = bytes.into_boxed_slice();
            let buffer = HyCodeBuffer {
                data: bytes.as_mut_ptr(),
                len: bytes.len(),
            };
            std::mem::forget(bytes);
            buffer
        }
        Err(_) => HyCodeBuffer {
            data: ptr::null_mut(),
            len: 0,
        },
    }
}

/// # Safety
/// The buffer must be an unmodified result of `hycode_core_list`, freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_buffer_free(buffer: HyCodeBuffer) {
    if !buffer.data.is_null() {
        drop(unsafe { Box::from_raw(ptr::slice_from_raw_parts_mut(buffer.data, buffer.len)) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_null_and_invalid_utf8_and_frees_owned_results() {
        unsafe {
            let token = hycode_cancel_new();
            for (pointer, len) in [(ptr::null(), 2), ([0xff].as_ptr(), 1)] {
                let buffer = hycode_core_list(pointer, len, ptr::null(), 0, false, token);
                let value: serde_json::Value =
                    serde_json::from_slice(slice::from_raw_parts(buffer.data, buffer.len)).unwrap();
                assert!(value["error"]["code"].is_string());
                hycode_buffer_free(buffer);
            }
            hycode_cancel(token);
            let root = std::env::temp_dir().to_string_lossy().into_owned();
            let buffer = hycode_core_list(root.as_ptr(), root.len(), ptr::null(), 0, false, token);
            let value: serde_json::Value =
                serde_json::from_slice(slice::from_raw_parts(buffer.data, buffer.len)).unwrap();
            assert_eq!(value["error"]["code"], "cancelled");
            hycode_buffer_free(buffer);
            hycode_cancel_free(token);
            hycode_buffer_free(HyCodeBuffer {
                data: ptr::null_mut(),
                len: 0,
            });
        }
    }
}
