#!/usr/bin/env bash
# Builds EngAssistant.app from the SPM executable. Run from repo root.
# Output: ./EngAssistant.app
set -euo pipefail

APP_NAME="EngAssistant"
SWIFT_PRODUCT="EngAssistant"

echo "→ swift build (release)"
swift build --configuration release --product "$SWIFT_PRODUCT"

BIN_PATH=".build/release/$SWIFT_PRODUCT"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "✗ Build product not found at $BIN_PATH"
    exit 1
fi

APP_DIR="./$APP_NAME.app"
echo "→ assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Sources/EngAssistantApp/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy SPM resource bundle if it exists (for built-in scenarios JSON, etc.)
if [[ -d ".build/release/EngAssistant_Core.bundle" ]]; then
    cp -R ".build/release/EngAssistant_Core.bundle" "$APP_DIR/Contents/Resources/"
fi

echo "✓ Built $APP_DIR"
echo "  To run: open $APP_DIR"
echo "  First-launch warning: right-click → Open to bypass Gatekeeper."
