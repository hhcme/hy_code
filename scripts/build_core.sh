#!/bin/bash
# Build only. Never launches the application or a UI test host.
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=14.0
export CARGO_BUILD_JOBS=2
cargo build --locked --release -p hycode-core
mkdir -p .build/native
cp target/release/libhycode_core.a .build/native/libhycode_core.a
