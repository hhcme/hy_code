#!/bin/bash
# 构建 Rust core，生成 Swift 绑定并打包 xcframework。
# 骨架阶段只产出 macOS arm64（Apple Silicon）切片；iOS 切片后续按需追加。
# 在打开 Xcode 工程或执行 xcodebuild 之前需要先运行本脚本。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
PKG="$ROOT/packages/HcCoreSwift"

cd "$CORE"
cargo build --release

BINDINGS_DIR="$PKG/Sources/HcCore"
HEADERS_DIR="$PKG/Headers"
mkdir -p "$BINDINGS_DIR" "$HEADERS_DIR"

./target/release/uniffi-bindgen generate \
  --library target/release/libhc_core.dylib \
  --language swift \
  --out-dir "$BINDINGS_DIR"

mv "$BINDINGS_DIR/hc_coreFFI.h" "$HEADERS_DIR/hc_coreFFI.h"
cp "$BINDINGS_DIR/hc_coreFFI.modulemap" "$HEADERS_DIR/module.modulemap"
rm -f "$BINDINGS_DIR/hc_coreFFI.modulemap"

rm -rf "$PKG/hc_coreFFI.xcframework"
xcodebuild -create-xcframework \
  -library target/release/libhc_core.a \
  -headers "$HEADERS_DIR" \
  -output "$PKG/hc_coreFFI.xcframework" > /dev/null

echo "core 构建完成：$PKG/hc_coreFFI.xcframework"
