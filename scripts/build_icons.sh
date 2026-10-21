#!/bin/bash
# Headless asset conversion only: no NSApplication, Dock or Finder interaction.
set -euo pipefail
cd "$(dirname "$0")/.."
source_image="app/macos/Resources/brand/icon.png"
properties="$(/usr/bin/sips -g pixelWidth -g pixelHeight -g hasAlpha "$source_image")"
if ! [[ "$properties" =~ pixelWidth:[[:space:]]1024([[:space:]]|$) && "$properties" =~ pixelHeight:[[:space:]]1024([[:space:]]|$) && "$properties" =~ hasAlpha:[[:space:]]yes ]]; then
    echo "HyCode icon must be a 1024x1024 PNG with an alpha channel." >&2
    exit 1
fi
mkdir -p .build/icons
icon_work="$(mktemp -d .build/icons/export.XXXXXX)"
trap 'rm -rf "$icon_work"' EXIT
iconset="$icon_work/HyCode.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((size * scale))
        suffix=""
        if [[ "$scale" == 2 ]]; then suffix="@2x"; fi
        /usr/bin/sips --resampleHeightWidth "$pixels" "$pixels" "$source_image" \
            --out "$iconset/icon_${size}x${size}${suffix}.png" > /dev/null
    done
done
/usr/bin/iconutil --convert icns --output "$icon_work/HyCode.icns" "$iconset"
mv -f "$icon_work/HyCode.icns" .build/icons/HyCode.icns
echo "Generated .build/icons/HyCode.icns (10 standard frames, 16-1024px)."
