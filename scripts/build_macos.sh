#!/bin/bash
# Create a local unsigned development app, without opening or installing it.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "HyCode currently builds for macOS / Apple Silicon only." >&2
    exit 1
fi
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    echo "Usage: bash scripts/build_macos.sh [debug|release]" >&2
    exit 1
fi
bash scripts/build_core.sh
if [[ ! -f tools/web-language-services/node_modules/typescript/lib/tsserver.js ]]; then
    bash scripts/setup_web_tools.sh
fi
node scripts/web_tools.mjs
python3 scripts/codex_runtime.py setup
python3 scripts/check_image_dependencies.py
python3 scripts/check_markup_dependencies.py
python3 scripts/check_native_language_dependencies.py
swift build --configuration "$configuration" --jobs 2 --product HyCode
binary_dir="$(swift build --configuration "$configuration" --show-bin-path)"
bash scripts/build_icons.sh
app_dir="build/HyCode.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/HyCode" "$app_dir/Contents/MacOS/.HyCode.new"
mv -f "$app_dir/Contents/MacOS/.HyCode.new" "$app_dir/Contents/MacOS/HyCode"
cp app/macos/Resources/Info.plist "$app_dir/Contents/Info.plist"
mkdir -p "$app_dir/Contents/Resources/third_party"
cp .build/icons/HyCode.icns "$app_dir/Contents/Resources/HyCode.icns"
cp app/macos/Resources/brand/icon.png "$app_dir/Contents/Resources/HyCode.png"
cp LICENSE THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/"
cp -R third_party/licenses "$app_dir/Contents/Resources/third_party/"
cp third_party/image-preview-crates.json third_party/markup-preview-crates.json third_party/native-language-crates.json "$app_dir/Contents/Resources/third_party/"
python3 scripts/codex_runtime.py stage "$app_dir/Contents/Resources/codex-runtime"
runtime_dir="$app_dir/Contents/Resources/web-language-services"
runtime_stage="$(mktemp -d "$app_dir/Contents/Resources/.web-language-services.XXXXXX")"
trap 'rm -rf "$runtime_stage"' EXIT
cp tools/web-language-services/package.json tools/web-language-services/package-lock.json tools/web-language-services/third-party.json "$runtime_stage/"
mkdir -p "$runtime_stage/native"
cp tools/web-language-services/native/config-language-server.mjs tools/web-language-services/native/schema-runtime.mjs "$runtime_stage/native/"
/usr/bin/ditto --norsrc --noextattr tools/web-language-services/schemas "$runtime_stage/schemas"
/usr/bin/ditto --norsrc --noextattr tools/web-language-services/node_modules "$runtime_stage/node_modules"
rm -rf "$runtime_dir"
mv "$runtime_stage" "$runtime_dir"
echo "Built $app_dir ($configuration, unsigned development build). Application was not launched."
