#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d /tmp/careerai-widgets.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$PROJECT_DIR"
swiftc -parse-as-library Tests/ApplicationWidgetTests.swift -o "$TEST_DIR/widget-tests"
"$TEST_DIR/widget-tests" "$PROJECT_DIR"
