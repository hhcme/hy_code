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
/* Additive ABI 1 cache maintenance, off UI. Live text handle: exclusive serial
 * access, JSON bool if parser/tree removed; revision/text are unchanged. Shared
 * cache: thread-safe, JSON count of unused compiled grammars removed; active
 * parsers keep ownership. No file, history, process or disk-cache operations.
 * Optional cancellation token borrowed through return; checked at commit, no
 * text/cache changes if already cancelled. Both owned result buffers use
 * existing free/panic rules. */
HyCodeTextResult hycode_text_trim_cache(HyCodeTextDocument *document,
                                      const HyCodeCancellation *token);
/* Shared eviction also borrows UTF-8 active path <=16KiB (empty if none), keeping
 * its fragment/embedded-language queries warm. Token checked after cache lock. */
HyCodeTextResult hycode_syntax_trim_cache(const uint8_t *protected_path, size_t path_len,
                                       const HyCodeCancellation *token);
/* Immutable independent page syntax; no document/FD/semantic access. UTF-8
 * <=262144 bytes /65536 UTF-16 units, path <=16KiB; start shifts capture spans.
 * Host serializes a dedicated background worker. Existing result/free rules. */
HyCodeTextResult hycode_syntax_fragment(const uint8_t *data, size_t len,
    const uint8_t *path, size_t path_len, size_t start);
/* Additive ABI 1, background serialized document access. Revision-bound preview
 * JSON {html,blocks:[{line,id}],markdown}; source <=32 MiB, generated HTML <=64 MiB,
 * <=8192 source blocks, <=100000 Markdown events /128 nesting. Raw HTML retained
 * for rendering only: host MUST disable content JS, network, navigation and
 * unapproved local resources. No file I/O or script execution here. Existing
 * HyCodeTextResult ownership/panic rules apply; free both buffers exactly once. */
HyCodeTextResult hycode_text_markup(const HyCodeTextDocument *document,
                                  uint64_t expected, bool markdown);

HyCodeTextResult hycode_text_markup_cancellable(const HyCodeTextDocument *document,
    uint64_t expected, bool markdown, const HyCodeCancellation *token);

/* Disk-backed text API, additive ABI 1. All calls serialized off UI. No mmap,
 * path lookup, GUI or process launch. Offsets are uint64 original-encoding bytes
 * excluding BOM; edit ranges are UTF-16 within the last returned 64KiB page.
 * open borrows an already authorized regular read fd; Rust duplicates/owns it.
 * Source versions are checked around reads/exports. Unsupported bytes fail the
 * requested page, never trigger lossy decoding or truncated full-file saves.
 * Whole-file copy/search uses 256KiB blocks. Optional cancellation tokens remain
 * alive through each call. Single edit/page <=1MiB, owned insert/history budget
 * 64MiB, <=128 undo entries /32MiB removed+inserted history. Rust alone owns history.
 * Both result buffers are freed once via hycode_buffer_free, on all outcomes.
 * Export writes only to an independent temp fd, original encoding/BOM. Host
 * coordinates/version-checks/fsyncs/atomically installs it, then calls saved.
 * Export freezes bounded undo ranges before replacing the old inode; saved
 * borrows the installed readable fd. History returns a prepared page atomically.
 */
typedef struct LargeDocument HyCodeLargeDocument;
HyCodeTextResult hycode_large_open(int32_t fd, HyCodeLargeDocument **output);
HyCodeTextResult hycode_large_page(HyCodeLargeDocument *document, uint64_t revision,
                                  uint64_t start, const HyCodeCancellation *token);
HyCodeTextResult hycode_large_replace(HyCodeLargeDocument *document, uint64_t revision,
    uint64_t page, size_t start, size_t length, const uint8_t *data, size_t len);
HyCodeTextResult hycode_large_status(HyCodeLargeDocument *document);
HyCodeTextResult hycode_large_history(HyCodeLargeDocument *document, uint64_t revision, bool redo);
HyCodeTextResult hycode_large_syntax(HyCodeLargeDocument *document, uint64_t revision,
    const uint8_t *path, size_t path_len, size_t start, size_t end);
HyCodeTextResult hycode_large_find(HyCodeLargeDocument *document, uint64_t revision,
    const uint8_t *text, size_t len, uint64_t from, const HyCodeCancellation *token);
HyCodeTextResult hycode_large_export(HyCodeLargeDocument *document, uint64_t revision,
    int32_t temporary_fd, const HyCodeCancellation *token);
HyCodeTextResult hycode_large_saved(HyCodeLargeDocument *document, uint64_t revision,
    int32_t installed_fd);
HyCodeTextResult hycode_large_markup(HyCodeLargeDocument *document, uint64_t revision,
    bool markdown, const HyCodeCancellation *token);
void hycode_large_free(HyCodeLargeDocument *document);

/* Additive ABI 1 offline SQL projection. Borrow UTF-8 <=256 KiB, no NUL.
 * dialect: 0 generic, 1 PostgreSQL, 2 MySQL, 3 SQLite, 4 MSSQL, 5 DuckDB,
 * 6 BigQuery, 7 Snowflake, 8 ANSI. <=30000 tokens /48 delimiter nesting /512 structural complexity /64 parse recursion.
 * One lazy bounded worker owns a 16 MiB stack for parser, visitor and AST drop.
 * Immutable JSON diagnostics/DDL/identifiers/optional comment-preserving format.
 * No I/O or execution. Background-only, cancellation before/after. Free both
 * result buffers once; revision is always 0 (caller owns session/version fence).
 */
HyCodeTextResult hycode_sql_analyze(const uint8_t *data, size_t len, uint32_t dialect, bool formatting);

/* Additive ABI 1 image entry. Borrow UTF-8 SVG <=2 MiB, edge 1..4096.
 * Returns premultiplied RGBA8 pixels, row stride width*4, or JSON error.
 * Caller owns/frees BOTH buffers using hycode_buffer_free, including errors.
 * No retained input, window, callbacks, or SVG resource file/network access.
 * Background-only. system_fonts permits one cached platform font discovery.
 * Host checks cancellation before/after this synchronous noninterruptible call.
 */
typedef struct {
    HyCodeBuffer pixels; HyCodeBuffer error;
    uint32_t width; uint32_t height;
    double source_width; double source_height;
} HyCodeImageResult;
HyCodeImageResult hycode_svg_render(const uint8_t *data, size_t len, uint32_t edge, bool system_fonts);

#ifdef __cplusplus
}
#endif
#endif
