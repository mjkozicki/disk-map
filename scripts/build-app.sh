#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift build --configuration release --product DiskMap
binary_dir="$(swift build --configuration release --show-bin-path)"
app_dir="$repo_root/build/Disk Map.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/DiskMap" "$app_dir/Contents/MacOS/DiskMap.new"
mv -f "$app_dir/Contents/MacOS/DiskMap.new" "$app_dir/Contents/MacOS/DiskMap"
cp "$repo_root/Resources/Info.plist" "$app_dir/Contents/Info.plist"
swift "$repo_root/scripts/make-icon.swift" "$repo_root/build/AppIcon.iconset"
iconutil -c icns "$repo_root/build/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
if [ -n "${DISKMAP_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$DISKMAP_SIGN_IDENTITY" "$app_dir"
else
  codesign --force --sign - "$app_dir"
fi
codesign --verify --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
