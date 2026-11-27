#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
APP_DIR="${CAREERAI_APP_DIR:-$PROJECT_DIR/build/OfferFlow.app}"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx14.0" -module-name CareerAI "$PROJECT_DIR"/Sources/*.swift -o "$APP_DIR/Contents/MacOS/CareerAI"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Sources/BossExtractor.js" "$APP_DIR/Contents/Resources/BossExtractor.js"
cp "$PROJECT_DIR/Sources/BossChat.js" "$APP_DIR/Contents/Resources/BossChat.js"
cp "$PROJECT_DIR/Sources/FeishuReader.js" "$APP_DIR/Contents/Resources/FeishuReader.js"
cp "$PROJECT_DIR/Sources/ApplicationAutofill.js" "$APP_DIR/Contents/Resources/ApplicationAutofill.js"
cp "$PROJECT_DIR/Sources/ApplicationSiteRules.json" "$APP_DIR/Contents/Resources/ApplicationSiteRules.json"
cp "$PROJECT_DIR/Sources/XiaohongshuReader.js" "$APP_DIR/Contents/Resources/XiaohongshuReader.js"
cp "$PROJECT_DIR/Sources/NowcoderReader.js" "$APP_DIR/Contents/Resources/NowcoderReader.js"
ditto "$PROJECT_DIR/Resources/Workspace" "$APP_DIR/Contents/Resources/Workspace"
swift "$PROJECT_DIR/scripts/create-icon.swift" "$PROJECT_DIR/build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
# Finder metadata on a copied local asset is not a signable bundle resource.
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true
codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
