#!/bin/bash
# Headless checks only. Swift Testing depends on workspace and geometry models,
# not the app target, AppKit, an application host, or UI automation.
set -euo pipefail
cd "$(dirname "$0")/.."
export CARGO_BUILD_JOBS=2
for script in scripts/build_core.sh scripts/build_icons.sh scripts/build_macos.sh scripts/check_native.sh scripts/setup_web_tools.sh; do
    bash -n "$script"
done
cargo fmt --all -- --check
xcrun swift-format lint --strict --recursive app/macos/Sources packages/HyCodeWorkspace tools/DirectoryProbe tools/DartProbe tools/DebugProbe tools/WebProbe tools/NativeLanguageProbe tools/MarkupRuleProbe tools/LargeFileProbe tools/CodexProbe tools/CodexSetup Package.swift
for script in tools/web-language-services/native/*.mjs; do
    node --check "$script"
done
node --test tools/web-language-services/native/schema-runtime.test.mjs
node --check scripts/web_tools.mjs
node scripts/web_tools.mjs
python3 scripts/check_image_dependencies.py
python3 scripts/check_markup_dependencies.py
python3 scripts/check_native_language_dependencies.py
python3 scripts/codex_runtime.py check
xcrun clang -x c -std=c11 -fsyntax-only -Wall -Wextra -Werror bindings/CHyCodeCore/include/hycode_core.h
xcrun clang++ -x c++ -std=c++17 -fsyntax-only -Wall -Wextra -Werror bindings/CHyCodeCore/include/hycode_core.h
cargo clippy --locked --workspace --all-targets -- -D warnings
# Cold grammar initialization shares caches; serialize these small Rust cases
# to avoid competing with each other (and the foreground) for the 100ms budget.
cargo test --locked --workspace -- --test-threads=1
bash scripts/build_core.sh
swift test --jobs 2 --disable-xctest
# Fixed JSON compiler only; temporary store, no WebView/application host/page.
swift run --skip-build HyCodeMarkupRuleProbe
python3 scripts/check_docs.py
git diff --check
