#!/bin/bash
set -euo pipefail

# Build a local, ad-hoc signed app. This is not a notarized release artifact.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '%s\n' 'ScreenSize requires macOS to build.' >&2
    exit 1
fi

swift build -c release --product ScreenSize
bin_dir="$(swift build --show-bin-path -c release)"
plutil -lint Resources/Info.plist

mkdir -p dist
staging_dir="$(mktemp -d "$project_dir/dist/.screensize-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
app_dir="$staging_dir/ScreenSize.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
install -m 755 "$bin_dir/ScreenSize" "$app_dir/Contents/MacOS/ScreenSize"
install -m 644 Resources/Info.plist "$app_dir/Contents/Info.plist"

codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"

rm -rf "$project_dir/dist/ScreenSize.app"
mv "$app_dir" "$project_dir/dist/ScreenSize.app"
printf '\nBuilt: %s\n' "$project_dir/dist/ScreenSize.app"
printf '%s\n' 'This local build is ad-hoc signed, not notarized.'
