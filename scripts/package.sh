#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="CalendarBar"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

cd "$ROOT_DIR"
BUILD_FLAGS=(--build-system native -c release --disable-sandbox -debug-info-format none)
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Keep the release bundle lean by removing local symbols before signing.
/usr/bin/strip -x "$APP_DIR/Contents/MacOS/$APP_NAME"

codesign \
    --force \
    --deep \
    --sign - \
    --requirements '=designated => identifier "com.benjamin.CalendarBar"' \
    "$APP_DIR"
echo "$APP_DIR"
