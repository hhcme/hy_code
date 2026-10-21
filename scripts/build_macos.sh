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
echo "Built $app_dir ($configuration, unsigned development build). Application was not launched."
