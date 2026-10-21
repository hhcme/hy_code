#!/bin/bash
# Headless checks only. Swift Testing depends on workspace and geometry models,
# not the app target, AppKit, an application host, or UI automation.
set -euo pipefail
cd "$(dirname "$0")/.."
export CARGO_BUILD_JOBS=2
for script in scripts/build_core.sh scripts/build_icons.sh scripts/build_macos.sh scripts/check_native.sh; do
    bash -n "$script"
done
cargo fmt --all -- --check
xcrun swift-format lint --strict --recursive app/macos/Sources packages/HyCodeWorkspace tools/DirectoryProbe Package.swift
xcrun clang -x c -std=c11 -fsyntax-only -Wall -Wextra -Werror bindings/CHyCodeCore/include/hycode_core.h
xcrun clang++ -x c++ -std=c++17 -fsyntax-only -Wall -Wextra -Werror bindings/CHyCodeCore/include/hycode_core.h
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace -- --test-threads=2
bash scripts/build_core.sh
swift test --jobs 2 --disable-xctest
python3 scripts/check_docs.py
git diff --check
