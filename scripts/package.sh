#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
APP_NAME="OfferFlow.app"
APP_DIR="${CAREERAI_APP_DIR:-$PROJECT_DIR/build/$APP_NAME}"
OUTPUT_DIR="$PROJECT_DIR/dist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/Info.plist")
ARTIFACT_NAME="OfferFlow-$VERSION-macOS-$(uname -m)"
STAGING_DIR=$(mktemp -d /tmp/offerflow-package.XXXXXX)
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$OUTPUT_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME"
find "$STAGING_DIR/$APP_NAME" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$STAGING_DIR/$APP_NAME" -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true
codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PROJECT_DIR/INSTALL.md" "$STAGING_DIR/INSTALL.md"
hdiutil create -volname "OfferFlow $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_DIR/$ARTIFACT_NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/$APP_NAME" "$OUTPUT_DIR/$ARTIFACT_NAME.zip"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ARTIFACT_NAME.dmg" "$ARTIFACT_NAME.zip" > SHA256SUMS.txt)
echo "$OUTPUT_DIR"
