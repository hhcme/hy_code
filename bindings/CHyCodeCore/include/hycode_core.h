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

/* Additive text API (ABI 1): Rust owns committed UTF-8 text and revision, no undo
 * history or file I/O. The platform owns IME/native undo and safe disk access.
 * All calls on a document must be serialized off the UI thread. No callbacks.
 * Both result buffers are caller-owned and freed with hycode_buffer_free,
 * including empty/failure results. error is UTF-8 WorkspaceFailure JSON.
 * Open accepts <=8 MiB UTF-8 (+optional BOM) or BOM-marked UTF-16 LE/BE.
 * Its value is JSON {text,encoding,has_bom,line_ending,byte_count}; revision 0.
 * Replace ranges count UTF-16 units, reject split surrogates/old revisions.
 * Bytes returns raw original-encoding content (not JSON), including BOM.
 * Free a successful document exactly once, after all borrowers finish.
 */
typedef struct TextDocument HyCodeTextDocument;
typedef struct { HyCodeBuffer value; HyCodeBuffer error; uint64_t revision; } HyCodeTextResult;
HyCodeTextResult hycode_text_open(const uint8_t *data, size_t len, HyCodeTextDocument **output);
HyCodeTextResult hycode_text_replace(HyCodeTextDocument *document, uint64_t expected,
                                   size_t start, size_t length, const uint8_t *data, size_t len);
HyCodeTextResult hycode_text_bytes(const HyCodeTextDocument *document, uint64_t expected);
/* Background-only versioned syntax. Borrow UTF-8 path (<=16 KiB); viewport start/end
 * are UTF-16 scalar boundaries, max 65,536 units. No file access. JSON value:
 * {language,status,start,length,spans:[{start,length,style}]}.
 * Parser caches belong to document. <=1 MiB syntax budget; larger text stays editable.
 * Parsing/query work cooperatively expires after 100ms; errors do not mutate text.
 * Same serialization, panic, buffer ownership and freeing rules as the text API.
 */
HyCodeTextResult hycode_text_syntax(HyCodeTextDocument *document, uint64_t expected,
                                  const uint8_t *path, size_t path_len, size_t start, size_t end);
void hycode_text_free(HyCodeTextDocument *document);

#ifdef __cplusplus
}
#endif
#endif
