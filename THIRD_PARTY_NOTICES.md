# Third-party notices

HyCode's own code is MIT licensed. Third-party components retain their own copyright and license terms.

The following dependency versions come from `Cargo.lock`; crate-source checksums are recorded there. For dual-licensed crates this distribution uses the MIT option. The Unicode data notice is retained in addition to MIT where required. Build-time dependencies are included for source/build provenance even when not part of the final executable.

| Component | Version | Upstream license expression | Retained notice | Upstream |
| --- | --- | --- | --- | --- |
| itoa | 1.0.18 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/itoa-1.0.18/LICENSE-MIT) | [source](https://github.com/dtolnay/itoa) |
| memchr | 2.8.3 | Unlicense OR MIT | [LICENSE-MIT](third_party/licenses/memchr-2.8.3/LICENSE-MIT) | [source](https://github.com/BurntSushi/memchr) |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/proc-macro2-1.0.107/LICENSE-MIT) | [source](https://github.com/dtolnay/proc-macro2) |
| quote | 1.0.47 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/quote-1.0.47/LICENSE-MIT) | [source](https://github.com/dtolnay/quote) |
| serde | 1.0.229 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde-1.0.229/LICENSE-MIT) | [source](https://github.com/serde-rs/serde) |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde_core-1.0.229/LICENSE-MIT) | [source](https://github.com/serde-rs/serde) |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde_derive-1.0.229/LICENSE-MIT) | [source](https://github.com/serde-rs/serde) |
| serde_json | 1.0.154 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/serde_json-1.0.154/LICENSE-MIT) | [source](https://github.com/serde-rs/json) |
| syn | 3.0.9 | MIT OR Apache-2.0 | [LICENSE-MIT](third_party/licenses/syn-3.0.9/LICENSE-MIT) | [source](https://github.com/dtolnay/syn) |
| unicode-ident | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 | [LICENSE-MIT](third_party/licenses/unicode-ident-1.0.27/LICENSE-MIT) + [LICENSE-UNICODE](third_party/licenses/unicode-ident-1.0.27/LICENSE-UNICODE) | [source](https://github.com/dtolnay/unicode-ident) |
| zmij | 1.0.23 | MIT | [LICENSE-MIT](third_party/licenses/zmij-1.0.23/LICENSE-MIT) | [source](https://github.com/dtolnay/zmij) |

The statically linked Rust 1.96.0 standard library has its own component inventory and licenses, copied from the installed official toolchain: [COPYRIGHT-library.html](third_party/licenses/rust-1.96.0/COPYRIGHT-library.html) and [license texts](third_party/licenses/rust-1.96.0/licenses/).

Swift, SwiftUI, AppKit, Foundation and SF Symbols are toolchain/system dependencies. This development build does not bundle a separate Swift runtime or Apple SDK. The SDK and operating system have their own terms; they are not relicensed as HyCode source.

Dependency updates must refresh the version inventory and notices. Current application artifacts are local development builds; signing, notarization and public binary distribution have not been validated.
