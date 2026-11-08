#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sign_identity="${NUBI_SIGN_IDENTITY:--}"
plugin_args=()
if [[ "${NUBI_SKIP_PACKAGE_PLUGIN_VALIDATION:-0}" == "1" ]]; then plugin_args=(-skipPackagePluginValidation); fi
xcodebuild -project Notch.xcodeproj -scheme Notch \
  -configuration Release -derivedDataPath build "${plugin_args[@]}" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$sign_identity" CODE_SIGNING_ALLOWED=YES build
codesign --verify --deep --strict build/Build/Products/Release/Nubi.app
