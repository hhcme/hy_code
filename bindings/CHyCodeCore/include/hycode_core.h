#ifndef HYCODE_CORE_H
#define HYCODE_CORE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ABI 1. UTF-8 byte paths; lengths count bytes, not characters. No callbacks. */
typedef struct HyCodeCancellation HyCodeCancellation;
typedef struct { uint8_t *data; size_t len; } HyCodeBuffer;
uint32_t hycode_core_abi_version(void);

/* Caller owns token. Cancellation is thread-safe; free only after all borrowers finish. */
HyCodeCancellation *hycode_cancel_new(void);
void hycode_cancel(const HyCodeCancellation *token);
void hycode_cancel_free(HyCodeCancellation *token);

/* Blocking I/O: never call on the UI thread. Inputs are borrowed for this call.
 * root is an explicitly selected workspace; relative must stay within it.
 * Symlinks are listed but not traversed. No writes, process launch or recursive scan.
 * Response is UTF-8 JSON: {snapshot: {...}|null, error: {code,message}|null}.
 * At most 20,000 entries / 50,000 examined per directory; truncation is explicit.
 * Caller owns the returned bytes and must free them exactly once, on any thread.
 * Rust panics are converted to errors; a null/empty buffer indicates encoding failure.
 */
HyCodeBuffer hycode_core_list(const uint8_t *root, size_t root_len,
                             const uint8_t *relative, size_t relative_len,
                             bool include_hidden, const HyCodeCancellation *token);
void hycode_buffer_free(HyCodeBuffer buffer);

#ifdef __cplusplus
}
#endif
#endif
