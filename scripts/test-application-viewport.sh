#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d /tmp/careerai-viewport-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$PROJECT_DIR"
swiftc -parse-as-library Sources/ApplicationBrowserControls.swift Sources/ApplicationViewport.swift Tests/ApplicationViewportTests.swift -o "$TEST_DIR/viewport-tests"
"$TEST_DIR/viewport-tests"
