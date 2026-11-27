#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d /tmp/careerai-moka-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$PROJECT_DIR"
swiftc -parse-as-library Sources/Models.swift Sources/BossTypes.swift Sources/ArkAI.swift Sources/ApplicationProfile.swift Sources/ApplicationAutofill.swift Tests/ApplicationMokaTests.swift -o "$TEST_DIR/moka-tests"
"$TEST_DIR/moka-tests" "$PROJECT_DIR"
