#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d /tmp/careerai-journey.XXXXXX)
SERVER_PID=''
trap '[[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$TEST_DIR"' EXIT
cd "$PROJECT_DIR"
python3 -u - "$TEST_DIR/port" "$PROJECT_DIR/Tests/Fixtures/application-journey" <<'PY' &
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
from pathlib import Path
import sys
server=ThreadingHTTPServer(('127.0.0.1',0),partial(SimpleHTTPRequestHandler,directory=sys.argv[2]))
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
PY
SERVER_PID=$!
for retry in {1..50}; do [[ -s "$TEST_DIR/port" ]] && break; sleep .1; done
TEST_APP="$TEST_DIR/JourneyTests.app"
mkdir -p "$TEST_APP/Contents/MacOS"
cat > "$TEST_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.careerai.journey-tests</string><key>CFBundleExecutable</key><string>journey-tests</string><key>CFBundleName</key><string>Career AI Local Tests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -parse-as-library Sources/Models.swift Sources/BossTypes.swift Sources/ArkAI.swift Sources/ApplicationProfile.swift Sources/ApplicationResumeParser.swift Sources/ApplicationProfileView.swift Sources/ApplicationAutofill.swift Sources/ApplicationValueAdapter.swift Sources/ApplicationJourney.swift Sources/ApplicationSiteRules.swift Sources/ApplicationJourneyAgent.swift Sources/ApplicationOptionMatcher.swift Sources/ApplicationViewport.swift Sources/ApplicationBrowser.swift Tests/ApplicationJourneyTests.swift -o "$TEST_APP/Contents/MacOS/journey-tests"
mkdir -p "$TEST_DIR/fixture-root/Sources"
cp Sources/ApplicationAutofill.js Sources/ApplicationSiteRules.json "$TEST_DIR/fixture-root/Sources/"
codesign --force --sign - "$TEST_APP"
open -W -n --stdout "$TEST_DIR/run.log" --stderr "$TEST_DIR/errors.log" "$TEST_APP" --args "$TEST_DIR/fixture-root" "http://127.0.0.1:$(cat "$TEST_DIR/port")/" "$@"
cat "$TEST_DIR/run.log" "$TEST_DIR/errors.log"
rg -q 'PASS zoomed page' "$TEST_DIR/run.log"

if [[ "$*" != *"--zoom-only"* && "$*" != *"--readonly-only"* && "$*" != *"--dialog-only"* ]]; then
  rg -q "PASS interrupted-save recovery" "$TEST_DIR/run.log"
  rg -q "PASS adapter guard" "$TEST_DIR/run.log"
fi
