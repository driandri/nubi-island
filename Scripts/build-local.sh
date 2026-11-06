#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Notch.xcodeproj -scheme Notch \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
codesign --verify --deep --strict build/Build/Products/Release/Nubi.app
