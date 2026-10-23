# Third-party notices

## Bundled Web and configuration language services (build 36)

Public npm JavaScript packages are fixed by [package-lock.json](tools/web-language-services/package-lock.json). All 119 direct/transitive entries (106 existing entries unchanged plus 13 YAML additions), registry archives, integrity metadata, license expressions and retained notice SHA-256 values are in [third-party.json](tools/web-language-services/third-party.json). Original LICENSE/COPYRIGHT/NOTICE files are retained in [third_party/licenses/npm/](third_party/licenses/npm/). `node scripts/web_tools.mjs` checks installed package metadata and retained files. External Node.js (minimum 22.22.2) is not copied into the app.

| Direct component | Version | License | Upstream |
| --- | --- | --- | --- |
| TypeScript | 6.0.3 | Apache-2.0 | [Microsoft](https://github.com/microsoft/TypeScript) |
| typescript-language-server | 6.0.2 | Apache-2.0 | [community LSP adapter](https://github.com/typescript-language-server/typescript-language-server) |
| @vue/language-server | 3.3.13 | MIT | [Vue language-tools](https://github.com/vuejs/language-tools) |
| yaml-language-server | 2.0.0 | MIT | [Red Hat](https://github.com/redhat-developer/yaml-language-server) |
| vscode-langservers-extracted | 4.10.0 | MIT | [public extraction project](https://github.com/hrsh7th/vscode-langservers-extracted) |

These are public packages, not resources extracted from a locally installed IDE. Transitive packages retain MIT, ISC, BSD-2-Clause, BSD-3-Clause or Apache-2.0 terms as listed individually; HyCode's MIT does not replace them.

Three missing archive notices are documented in [license-supplements.json](tools/web-language-services/license-supplements.json). @vscode/l10n and boolbase use upstream license texts pinned to repository commits. **@johnsoncodehk/pug-beautify 0.2.2 declares MIT but its npm archive and inspected upstream have no standalone license text.** Its original [package declaration](third_party/licenses/npm/johnsoncodehk__pug-beautify-0.2.2/package.json) and [README](third_party/licenses/npm/johnsoncodehk__pug-beautify-0.2.2/README.md) are retained without inventing copyright text. This limitation remains explicit for future binary distribution review.

## Bundled offline schemas (build 36)

14 original JSON Schema files are pinned to [SchemaStore commit 4b9347599acb42276483fc514f641505e205d331](https://github.com/SchemaStore/schemastore/tree/4b9347599acb42276483fc514f641505e205d331). The four associations cover package.json, TS/JS configuration, GitHub workflows and pubspec; the remaining files resolve their transitive references offline. Original bytes, source URLs and SHA-256 values are in [catalog.json](tools/web-language-services/schemas/catalog.json). Original [LICENSE](third_party/licenses/schemastore-4b9347599acb/LICENSE) and [NOTICE](third_party/licenses/schemastore-4b9347599acb/NOTICE) are retained and bundled. JSON Schema Store, Copyright 2015-Current Mads Kristensen and Contributors, Apache-2.0. These data retain upstream terms; HyCode MIT does not replace them.

## Rust and platform dependencies

HyCode's own code is MIT licensed. Third-party components retain their own copyright and license terms.

The versions and crate-source checksums are fixed in `Cargo.lock`. For dual-licensed crates this distribution uses the MIT option; foldhash uses Zlib. Unicode and bundled subcomponent notices are retained where supplied. Build-time dependencies are included for source/build provenance. Missing crate license files were obtained from the upstream repository at the commit recorded in that crate's `.cargo_vcs_info.json`.

| Component | Version | Upstream license expression | Retained notice | Upstream |
| --- | --- | --- | --- | --- |
| aho-corasick | 1.1.5 | Unlicense OR MIT | [LICENSE-MIT](third_party/licenses/aho-corasick-1.1.5/LICENSE-MIT) | [source](https://github.com/BurntSushi/aho-corasick) |
| cc | 1.2.67 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/cc-1.2.67/LICENSE-MIT) | [source](https://github.com/rust-lang/cc-rs) |
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


## Image preview additions (build 34)

SVG rendering uses resvg/usvg with text and system-font discovery, without SVGZ or embedded raster-image features. All 52 new direct/transitive crates are fixed by Cargo.lock; their selected licenses, archive checksums and retained-notice SHA-256 values are recorded in [image-preview-crates.json](third_party/image-preview-crates.json). There are 89 Cargo registry dependencies in total. For dual licenses this build chooses MIT; the additions also retain BSD-2-Clause, BSD-3-Clause and Zlib notices. Platform font files are read locally at runtime and are not bundled or relicensed. ImageIO/CoreGraphics are platform dependencies.

| Component | Version | Upstream license expression | Retained notices | Upstream |
| --- | --- | --- | --- | --- |
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 | [LICENSE-0BSD](third_party/licenses/adler2-2.0.1/LICENSE-0BSD) / [LICENSE-APACHE](third_party/licenses/adler2-2.0.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/adler2-2.0.1/LICENSE-MIT) | [upstream](https://github.com/oyvindln/adler2) |
| arrayref | 0.3.9 | BSD-2-Clause | [LICENSE](third_party/licenses/arrayref-0.3.9/LICENSE) | [upstream](https://github.com/droundy/arrayref) |
| arrayvec | 0.7.8 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/arrayvec-0.7.8/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/arrayvec-0.7.8/LICENSE-MIT) | [upstream](https://github.com/bluss/arrayvec) |
| autocfg | 1.5.1 | Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/autocfg-1.5.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/autocfg-1.5.1/LICENSE-MIT) | [upstream](https://github.com/cuviper/autocfg) |
| base64 | 0.23.1 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/base64-0.23.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/base64-0.23.1/LICENSE-MIT) | [upstream](https://github.com/marshallpierce/rust-base64) |
| bitflags | 2.13.2 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/bitflags-2.13.2/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/bitflags-2.13.2/LICENSE-MIT) | [upstream](https://github.com/bitflags/bitflags) |
| bytemuck | 1.25.2 | Zlib OR Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/bytemuck-1.25.2/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/bytemuck-1.25.2/LICENSE-MIT) / [LICENSE-ZLIB](third_party/licenses/bytemuck-1.25.2/LICENSE-ZLIB) | [upstream](https://github.com/Lokathor/bytemuck) |
| bytemuck_derive | 1.12.1 | Zlib OR Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/bytemuck_derive-1.12.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/bytemuck_derive-1.12.1/LICENSE-MIT) / [LICENSE-ZLIB](third_party/licenses/bytemuck_derive-1.12.1/LICENSE-ZLIB) | [upstream](https://github.com/Lokathor/bytemuck) |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/cfg-if-1.0.5/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/cfg-if-1.0.5/LICENSE-MIT) | [upstream](https://github.com/rust-lang/cfg-if) |
| crc32fast | 1.5.3 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/crc32fast-1.5.3/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/crc32fast-1.5.3/LICENSE-MIT) | [upstream](https://github.com/srijs/rust-crc32fast) |
| data-url | 0.3.2 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/data-url-0.3.2/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/data-url-0.3.2/LICENSE-MIT) | [upstream](https://github.com/servo/rust-url) |
| euclid | 0.22.14 | MIT OR Apache-2.0 | [COPYRIGHT](third_party/licenses/euclid-0.22.14/COPYRIGHT) / [LICENSE-APACHE](third_party/licenses/euclid-0.22.14/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/euclid-0.22.14/LICENSE-MIT) | [upstream](https://github.com/servo/euclid) |
| fdeflate | 0.3.7 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/fdeflate-0.3.7/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/fdeflate-0.3.7/LICENSE-MIT) | [upstream](https://github.com/image-rs/fdeflate) |
| flate2 | 1.1.10 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/flate2-1.1.10/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/flate2-1.1.10/LICENSE-MIT) | [upstream](https://github.com/rust-lang/flate2-rs) |
| float-cmp | 0.9.0 | MIT | [LICENSE](third_party/licenses/float-cmp-0.9.0/LICENSE) | [upstream](https://github.com/mikedilger/float-cmp) |
| font-types | 0.12.7 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/font-types-0.12.7/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/font-types-0.12.7/LICENSE-MIT) | [upstream](https://github.com/googlefonts/fontations) |
| fontconfig-parser | 0.5.8 | MIT | [LICENSE](third_party/licenses/fontconfig-parser-0.5.8/LICENSE) | [upstream](https://github.com/Riey/fontconfig-parser) |
| fontdb | 0.24.0 | MIT | [LICENSE](third_party/licenses/fontdb-0.24.0/LICENSE) / [LICENSE.txt](third_party/licenses/fontdb-0.24.0/tests/fonts/LICENSE.txt) | [upstream](https://github.com/RazrFalcon/fontdb) |
| harfrust | 0.12.0 | MIT | [LICENSE](third_party/licenses/harfrust-0.12.0/LICENSE) | [upstream](https://github.com/harfbuzz/harfrust) |
| imagesize | 0.15.0 | MIT | [LICENSE](third_party/licenses/imagesize-0.15.0/LICENSE) | [upstream](https://github.com/Roughsketch/imagesize) |
| kurbo | 0.13.1 | Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/kurbo-0.13.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/kurbo-0.13.1/LICENSE-MIT) | [upstream](https://github.com/linebender/kurbo) |
| log | 0.4.34 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/log-0.4.34/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/log-0.4.34/LICENSE-MIT) | [upstream](https://github.com/rust-lang/log) |
| miniz_oxide | 0.8.9 | MIT OR Zlib OR Apache-2.0 | [LICENSE](third_party/licenses/miniz_oxide-0.8.9/LICENSE) / [LICENSE-APACHE.md](third_party/licenses/miniz_oxide-0.8.9/LICENSE-APACHE.md) / [LICENSE-MIT.md](third_party/licenses/miniz_oxide-0.8.9/LICENSE-MIT.md) / [LICENSE-ZLIB.md](third_party/licenses/miniz_oxide-0.8.9/LICENSE-ZLIB.md) | [upstream](https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide) |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 | [LICENSE](third_party/licenses/miniz_oxide-0.9.1/LICENSE) / [LICENSE-APACHE.md](third_party/licenses/miniz_oxide-0.9.1/LICENSE-APACHE.md) / [LICENSE-MIT.md](third_party/licenses/miniz_oxide-0.9.1/LICENSE-MIT.md) / [LICENSE-ZLIB.md](third_party/licenses/miniz_oxide-0.9.1/LICENSE-ZLIB.md) | [upstream](https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide) |
| num-traits | 0.2.19 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/num-traits-0.2.19/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/num-traits-0.2.19/LICENSE-MIT) | [upstream](https://github.com/rust-num/num-traits) |
| once_cell | 1.21.4 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/once_cell-1.21.4/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/once_cell-1.21.4/LICENSE-MIT) | [upstream](https://github.com/matklad/once_cell) |
| pico-args | 0.5.0 | MIT | [LICENSE](third_party/licenses/pico-args-0.5.0/LICENSE) | [upstream](https://github.com/RazrFalcon/pico-args) |
| png | 0.18.1 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/png-0.18.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/png-0.18.1/LICENSE-MIT) | [upstream](https://github.com/image-rs/image-png) |
| polycool | 0.4.0 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/polycool-0.4.0/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/polycool-0.4.0/LICENSE-MIT) | [upstream](https://github.com/linebender/kurbo) |
| read-fonts | 0.41.0 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/read-fonts-0.41.0/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/read-fonts-0.41.0/LICENSE-MIT) | [upstream](https://github.com/googlefonts/fontations) |
| resvg | 0.48.1 | Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/resvg-0.48.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/resvg-0.48.1/LICENSE-MIT) | [upstream](https://github.com/linebender/resvg) |
| rgb | 0.8.53 | MIT | [LICENSE](third_party/licenses/rgb-0.8.53/LICENSE) | [upstream](https://github.com/kornelski/rust-rgb) |
| roxmltree | 0.20.0 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/roxmltree-0.20.0/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/roxmltree-0.20.0/LICENSE-MIT) | [upstream](https://github.com/RazrFalcon/roxmltree) |
| roxmltree | 0.21.1 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/roxmltree-0.21.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/roxmltree-0.21.1/LICENSE-MIT) | [upstream](https://github.com/RazrFalcon/roxmltree) |
| simd-adler32 | 0.3.10 | MIT | [LICENSE.md](third_party/licenses/simd-adler32-0.3.10/LICENSE.md) | [upstream](https://github.com/mcountryman/simd-adler32) |
| simplecss | 0.2.2 | Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/simplecss-0.2.2/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/simplecss-0.2.2/LICENSE-MIT) | [upstream](https://github.com/linebender/simplecss) |
| siphasher | 1.0.4 | MIT OR Apache-2.0 | [COPYING](third_party/licenses/siphasher-1.0.4/COPYING) / [LICENSE-APACHE](third_party/licenses/siphasher-1.0.4/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/siphasher-1.0.4/LICENSE-MIT) | [upstream](https://github.com/jedisct1/rust-siphash) |
| skrifa | 0.44.0 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/skrifa-0.44.0/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/skrifa-0.44.0/LICENSE-MIT) | [upstream](https://github.com/googlefonts/fontations) |
| slotmap | 1.1.1 | Zlib | [LICENSE](third_party/licenses/slotmap-1.1.1/LICENSE) | [upstream](https://github.com/orlp/slotmap) |
| smallvec | 1.16.3 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/smallvec-1.16.3/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/smallvec-1.16.3/LICENSE-MIT) | [upstream](https://github.com/servo/rust-smallvec) |
| strict-num | 0.1.1 | MIT | [LICENSE](third_party/licenses/strict-num-0.1.1/LICENSE) | [upstream](https://github.com/RazrFalcon/strict-num) |
| svgtypes | 0.16.1 | Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/svgtypes-0.16.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/svgtypes-0.16.1/LICENSE-MIT) | [upstream](https://github.com/linebender/svgtypes) |
| tiny-skia | 0.12.0 | BSD-3-Clause | [LICENSE](third_party/licenses/tiny-skia-0.12.0/LICENSE) | [upstream](https://github.com/linebender/tiny-skia) |
| tiny-skia-path | 0.12.0 | BSD-3-Clause | [LICENSE](third_party/licenses/tiny-skia-path-0.12.0/LICENSE) | [upstream](https://github.com/linebender/tiny-skia/tree/master/path) |
| tinyvec | 1.13.3 | Zlib OR Apache-2.0 OR MIT | [LICENSE-APACHE.md](third_party/licenses/tinyvec-1.13.3/LICENSE-APACHE.md) / [LICENSE-MIT.md](third_party/licenses/tinyvec-1.13.3/LICENSE-MIT.md) / [LICENSE-ZLIB.md](third_party/licenses/tinyvec-1.13.3/LICENSE-ZLIB.md) | [upstream](https://github.com/Lokathor/tinyvec) |
| unicode-bidi | 0.3.18 | MIT OR Apache-2.0 | [COPYRIGHT](third_party/licenses/unicode-bidi-0.3.18/COPYRIGHT) / [LICENSE-APACHE](third_party/licenses/unicode-bidi-0.3.18/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/unicode-bidi-0.3.18/LICENSE-MIT) | [upstream](https://github.com/servo/unicode-bidi) |
| unicode-script | 0.5.8 | MIT OR Apache-2.0 | [LICENSE-APACHE](third_party/licenses/unicode-script-0.5.8/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/unicode-script-0.5.8/LICENSE-MIT) | [upstream](https://github.com/unicode-rs/unicode-script) |
| unicode-vo | 0.1.0 | MIT/Apache-2.0 | [LICENSE-APACHE](third_party/licenses/unicode-vo-0.1.0/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/unicode-vo-0.1.0/LICENSE-MIT) | [upstream](https://github.com/RazrFalcon/unicode-vo) |
| usvg | 0.48.1 | Apache-2.0 OR MIT | [LICENSE-APACHE](third_party/licenses/usvg-0.48.1/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/usvg-0.48.1/LICENSE-MIT) | [upstream](https://github.com/linebender/resvg) |
| version_check | 0.9.5 | MIT/Apache-2.0 | [LICENSE-APACHE](third_party/licenses/version_check-0.9.5/LICENSE-APACHE) / [LICENSE-MIT](third_party/licenses/version_check-0.9.5/LICENSE-MIT) | [upstream](https://github.com/SergioBenitez/version_check) |
| xmlwriter | 0.1.0 | MIT | [LICENSE](third_party/licenses/xmlwriter-0.1.0/LICENSE) | [upstream](https://github.com/RazrFalcon/xmlwriter) |
| zlib-rs | 0.6.8 | Zlib | [LICENSE](third_party/licenses/zlib-rs-0.6.8/LICENSE) | [upstream](https://github.com/trifectatechfoundation/zlib-rs) |

## Markdown preview (build 37)

Statically linked [pulldown-cmark 0.13.5](https://github.com/pulldown-cmark/pulldown-cmark) and pulldown-cmark-escape 0.11.0 use MIT; [unicase 2.10.0](https://github.com/seanmonstar/unicase) is MIT OR Apache-2.0, with the MIT option selected. Exact registry checksums, original notice paths and SHA-256 values are retained in [markup-preview-crates.json](third_party/markup-preview-crates.json); original notices are bundled. WebKit is a macOS system dependency, not redistributed or relicensed by HyCode. No IDE renderer or private-source code was copied.

## Swift, Java and offline SQL (build 38)

The 16 new or changed registry packages are pinned in Cargo.lock and [native-language-crates.json](third_party/native-language-crates.json), including exact archive checksums, upstream repositories, selected licenses and original-notice SHA-256 values. All 107 Cargo registry entries retain their own terms. The SQL grammar requires cc ~1.2.1; Cargo therefore selects cc 1.2.67 instead of baseline 1.9.0. All other baseline versions and checksums are retained. Original notices are bundled even for build-time and non-macOS transitive packages.

| Component | Version | Selected license | Upstream |
| --- | --- | --- | --- |
| ar_archive_writer | 0.5.3 | Apache-2.0 WITH LLVM-exception | [upstream](https://github.com/rust-lang/ar_archive_writer) |
| cc | 1.2.67 | MIT | [upstream](https://github.com/rust-lang/cc-rs) |
| libc | 0.2.191 | MIT | [upstream](https://github.com/rust-lang/libc) |
| object | 0.39.1 | MIT | [upstream](https://github.com/gimli-rs/object) |
| psm | 0.1.32 | MIT | [upstream](https://github.com/rust-lang/stacker/) |
| recursive | 0.1.1 | MIT | [upstream](https://github.com/orlp/recursive) |
| recursive-proc-macro-impl | 0.1.1 | MIT | [upstream](https://github.com/orlp/recursive) |
| sqlparser | 0.63.0 | Apache-2.0 | [upstream](https://github.com/apache/datafusion-sqlparser-rs) |
| sqlparser_derive | 0.6.0 | Apache-2.0 | [upstream](https://github.com/sqlparser-rs/sqlparser-rs) |
| stacker | 0.1.25 | MIT | [upstream](https://github.com/rust-lang/stacker) |
| syn | 2.0.119 | MIT | [upstream](https://github.com/dtolnay/syn) |
| tree-sitter-java | 0.23.5 | MIT | [upstream](https://github.com/tree-sitter/tree-sitter-java) |
| tree-sitter-sequel | 0.3.11 | MIT | [upstream](https://github.com/derekstride/tree-sitter-sql.git) |
| tree-sitter-swift | 0.7.4 | MIT | [upstream](https://github.com/alex-pinkus/tree-sitter-swift) |
| windows-link | 0.2.1 | MIT | [upstream](https://github.com/microsoft/windows-rs) |
| windows-sys | 0.61.2 | MIT | [upstream](https://github.com/microsoft/windows-rs) |

The Java and SQL grammar archives omitted standalone license files. Their retained MIT notices come from immutable upstream commits recorded as notice_source in the inventory; original bytes were not rewritten. The LLVM exception in ar_archive_writer is preserved in its complete original license.

[SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp/blob/main/LICENSE.txt) uses Apache-2.0 with its runtime-library exception; [Eclipse JDT LS 1.50.0](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/v1.50.0/LICENSE) uses EPL-2.0. These servers, JDK and toolchains are user-installed external tools and are not redistributed in the application. Protocol integration does not copy private IDE code. Installed distributions may include additional upstream components under their own terms.
