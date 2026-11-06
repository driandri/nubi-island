#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build-local.sh

app="build/Build/Products/Release/Nubi.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
package="Nubi-${version}-local"
mkdir -p build/packages
staging=$(mktemp -d "$PWD/build/packages/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/$package"
ditto "$app" "$staging/$package/Nubi.app"
cp Docs/INSTALL.md "$staging/$package/INSTALL.md"
cp Docs/ROADMAP.md "$staging/$package/LIMITATIONS.md"
codesign --verify --deep --strict "$staging/$package/Nubi.app"
archive="$PWD/build/packages/$package.zip"
ditto -c -k --sequesterRsrc --keepParent "$staging/$package" "$staging/package.zip"
# Verify the actual archive before publishing it to the output directory.
ditto -x -k "$staging/package.zip" "$staging/extracted"
codesign --verify --deep --strict "$staging/extracted/$package/Nubi.app"
cmp "$app/Contents/MacOS/Nubi" "$staging/extracted/$package/Nubi.app/Contents/MacOS/Nubi"
mv "$staging/package.zip" "$archive"
(cd build/packages && shasum -a 256 "$package.zip" > "$package.zip.sha256")
printf 'Package ready: %s\n' "$archive"
