# Third-party notices

## Bundled Web language services (build 28)

Public npm JavaScript packages are fixed by [package-lock.json](tools/web-language-services/package-lock.json). All 106 direct/transitive entries, registry archives, integrity metadata, license expressions and retained notice SHA-256 values are in [third-party.json](tools/web-language-services/third-party.json). Original LICENSE/COPYRIGHT/NOTICE files are retained in [third_party/licenses/npm/](third_party/licenses/npm/). `node scripts/web_tools.mjs` checks installed package metadata and retained files. External Node.js (minimum 22.22.2) is not copied into the app.

| Direct component | Version | License | Upstream |
| --- | --- | --- | --- |
| TypeScript | 6.0.3 | Apache-2.0 | [Microsoft](https://github.com/microsoft/TypeScript) |
| typescript-language-server | 6.0.2 | Apache-2.0 | [community LSP adapter](https://github.com/typescript-language-server/typescript-language-server) |
| @vue/language-server | 3.3.13 | MIT | [Vue language-tools](https://github.com/vuejs/language-tools) |
| vscode-langservers-extracted | 4.10.0 | MIT | [public extraction project](https://github.com/hrsh7th/vscode-langservers-extracted) |

These are public packages, not resources extracted from a locally installed IDE. Transitive packages retain MIT, ISC, BSD-2-Clause, BSD-3-Clause or Apache-2.0 terms as listed individually; HyCode's MIT does not replace them.

Three missing archive notices are documented in [license-supplements.json](tools/web-language-services/license-supplements.json). @vscode/l10n and boolbase use upstream license texts pinned to repository commits. **@johnsoncodehk/pug-beautify 0.2.2 declares MIT but its npm archive and inspected upstream have no standalone license text.** Its original [package declaration](third_party/licenses/npm/johnsoncodehk__pug-beautify-0.2.2/package.json) and [README](third_party/licenses/npm/johnsoncodehk__pug-beautify-0.2.2/README.md) are retained without inventing copyright text. This limitation remains explicit for future binary distribution review.

## Rust and platform dependencies

HyCode's own code is MIT licensed. Third-party components retain their own copyright and license terms.

The versions and crate-source checksums are fixed in `Cargo.lock`. For dual-licensed crates this distribution uses the MIT option; foldhash uses Zlib. Unicode and bundled subcomponent notices are retained where supplied. Build-time dependencies are included for source/build provenance. Missing crate license files were obtained from the upstream repository at the commit recorded in that crate's `.cargo_vcs_info.json`.

| Component | Version | Upstream license expression | Retained notice | Upstream |
| --- | --- | --- | --- | --- |
| aho-corasick | 1.1.5 | Unlicense OR MIT | [LICENSE-MIT](third_party/licenses/aho-corasick-1.1.5/LICENSE-MIT) | [source](https://github.com/BurntSushi/aho-corasick) |
| cc | 1.9.0 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/cc-1.9.0/LICENSE-MIT) | [source](https://github.com/rust-lang/cc-rs) |
| equivalent | 1.0.3 | Apache-2.0 OR MIT | [LICENSE-MIT](third_party/licenses/equivalent-1.0.3/LICENSE-MIT) | [source](https://github.com/indexmap-rs/equivalent) |
| find-msvc-tools | 0.1.15 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/find-msvc-tools-0.1.15/LICENSE-MIT) | [source](https://github.com/rust-lang/cc-rs) |
| foldhash | 0.2.0 | Zlib | [LICENSE](third_party/licenses/foldhash-0.2.0/LICENSE) | [source](https://github.com/orlp/foldhash) |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/hashbrown-0.17.1/LICENSE-MIT) | [source](https://github.com/rust-lang/hashbrown) |
| indexmap | 2.14.2 | Apache-2.0 OR MIT | [LICENSE-MIT](third_party/licenses/indexmap-2.14.2/LICENSE-MIT) | [source](https://github.com/indexmap-rs/indexmap) |
| itoa | 1.0.18 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/itoa-1.0.18/LICENSE-MIT) | [source](https://github.com/dtolnay/itoa) |
| memchr | 2.8.3 | Unlicense OR MIT | [LICENSE-MIT](third_party/licenses/memchr-2.8.3/LICENSE-MIT) | [source](https://github.com/BurntSushi/memchr) |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/proc-macro2-1.0.107/LICENSE-MIT) | [source](https://github.com/dtolnay/proc-macro2) |
| quote | 1.0.47 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/quote-1.0.47/LICENSE-MIT) | [source](https://github.com/dtolnay/quote) |
| regex | 1.13.1 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/regex-1.13.1/LICENSE-MIT) | [source](https://github.com/rust-lang/regex) |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/regex-automata-0.4.18/LICENSE-MIT) | [source](https://github.com/rust-lang/regex) |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/regex-syntax-0.8.11/LICENSE-MIT) + [LICENSE-UNICODE](third_party/licenses/regex-syntax-0.8.11/src/unicode_tables/LICENSE-UNICODE) | [source](https://github.com/rust-lang/regex) |
| serde | 1.0.229 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde-1.0.229/LICENSE-MIT) | [source](https://github.com/serde-rs/serde) |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde_core-1.0.229/LICENSE-MIT) | [source](https://github.com/serde-rs/serde) |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde_derive-1.0.229/LICENSE-MIT) | [source](https://github.com/serde-rs/serde) |
| serde_json | 1.0.154 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde_json-1.0.154/LICENSE-MIT) | [source](https://github.com/serde-rs/json) |
| shlex | 2.0.1 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/shlex-2.0.1/LICENSE-MIT) | [source](https://github.com/comex/rust-shlex) |
| streaming-iterator | 0.1.9 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/streaming-iterator-0.1.9/LICENSE-MIT) | [source](https://github.com/sfackler/streaming-iterator) |
| syn | 3.0.9 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/syn-3.0.9/LICENSE-MIT) | [source](https://github.com/dtolnay/syn) |
| tree-sitter | 0.27.1 | MIT | [LICENSE](third_party/licenses/tree-sitter-0.27.1/LICENSE) + [LICENSE](third_party/licenses/tree-sitter-0.27.1/src/unicode/LICENSE) + [LICENSE](third_party/licenses/tree-sitter-0.27.1/src/wasm-stdlib/libc/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter) |
| tree-sitter-c | 0.24.2 | MIT | [LICENSE](third_party/licenses/tree-sitter-c-0.24.2/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-c) |
| tree-sitter-cpp | 0.23.4 | MIT | [LICENSE](third_party/licenses/tree-sitter-cpp-0.23.4/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-cpp) |
| tree-sitter-css | 0.25.0 | MIT | [LICENSE](third_party/licenses/tree-sitter-css-0.25.0/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-css) |
| tree-sitter-dart | 0.2.0 | MIT | [LICENSE](third_party/licenses/tree-sitter-dart-0.2.0/LICENSE) | [source](https://github.com/nielsenko/tree-sitter-dart) |
| tree-sitter-html | 0.23.2 | MIT | [LICENSE](third_party/licenses/tree-sitter-html-0.23.2/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-html) |
| tree-sitter-javascript | 0.25.0 | MIT | [LICENSE](third_party/licenses/tree-sitter-javascript-0.25.0/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-javascript) |
| tree-sitter-json | 0.24.8 | MIT | [LICENSE](third_party/licenses/tree-sitter-json-0.24.8/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-json) |
| tree-sitter-language | 0.1.9 | MIT | [LICENSE](third_party/licenses/tree-sitter-language-0.1.9/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter) |
| tree-sitter-rust | 0.24.2 | MIT | [LICENSE](third_party/licenses/tree-sitter-rust-0.24.2/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-rust) |
| tree-sitter-toml-ng | 0.7.0 | MIT | [LICENSE](third_party/licenses/tree-sitter-toml-ng-0.7.0/LICENSE) | [source](https://github.com/tree-sitter-grammars/tree-sitter-toml) |
| tree-sitter-typescript | 0.23.2 | MIT | [LICENSE](third_party/licenses/tree-sitter-typescript-0.23.2/LICENSE) | [source](https://github.com/tree-sitter/tree-sitter-typescript) |
| tree-sitter-vue-next | 0.1.0 | MIT | [LICENSE](third_party/licenses/tree-sitter-vue-next-0.1.0/LICENSE) | [source](https://github.com/jamie8johnson/tree-sitter-vue) |
| tree-sitter-yaml | 0.7.2 | MIT | [LICENSE](third_party/licenses/tree-sitter-yaml-0.7.2/LICENSE) | [source](https://github.com/tree-sitter-grammars/tree-sitter-yaml) |
| unicode-ident | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 | [LICENSE-MIT](third_party/licenses/unicode-ident-1.0.27/LICENSE-MIT) + [LICENSE-UNICODE](third_party/licenses/unicode-ident-1.0.27/LICENSE-UNICODE) | [source](https://github.com/dtolnay/unicode-ident) |
| zmij | 1.0.23 | MIT | [LICENSE-MIT](third_party/licenses/zmij-1.0.23/LICENSE-MIT) | [source](https://github.com/dtolnay/zmij) |

The statically linked Rust 1.96.0 standard library has its own inventory and licenses: [COPYRIGHT-library.html](third_party/licenses/rust-1.96.0/COPYRIGHT-library.html) and [license texts](third_party/licenses/rust-1.96.0/licenses/).

Swift, SwiftUI, AppKit, Foundation and SF Symbols are toolchain/system dependencies. This development build does not bundle a separate Swift runtime or Apple SDK. The SDK and operating system have their own terms; they are not relicensed as HyCode source.

Tree-sitter and its grammar packages are statically linked. The Dart and Vue grammars are community projects, not official Dart or Vue language analyzers. Syntax coloring does not provide semantic diagnostics or references.

Dependency updates must refresh the inventory and notices. Application artifacts remain local development builds; signing, notarization and public binary distribution have not been validated.

## External Dart / Flutter SDK tools (not redistributed)

HyCode can invoke a user-selected installed Dart Analysis Server, Dart/Flutter Pub, Flutter debug adapter and explicit device/build/test tools through stdio/CLI. No SDK binaries, source, snapshots, or IDE plugins are copied into this repository or bundled in the app by this feature. Language protocol integration was checked with Dart 3.11.5; DAP was checked with an owned stdio fixture, while this SDK fork rejected VM Service launch flags in the generated console probe (not passed). The local Flutter installation reports 3.41.10-ohos-0.0.2-beta, which is not a compatibility claim for all forks or releases.

Upstream Dart SDK and Flutter are BSD-3-Clause; their own SDK distributions retain their licenses and third-party notices. Sources: [Dart SDK 3.11.5](https://github.com/dart-lang/sdk/tree/3.11.5), [Dart LICENSE](https://github.com/dart-lang/sdk/blob/3.11.5/LICENSE), [Flutter](https://github.com/flutter/flutter), [Flutter LICENSE](https://github.com/flutter/flutter/blob/3.41.5/LICENSE). Additional components in an installed SDK/fork remain that distribution's responsibility. See [Dart/Flutter tooling](docs/DART_FLUTTER.md) for invocation, lifecycle, version and verification limits.
