#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d /tmp/careerai-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
node --check "$PROJECT_DIR/Sources/BossExtractor.js"
node --check "$PROJECT_DIR/Sources/BossChat.js"
node -e 'const fs = require("fs"); const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor; new AsyncFunction("mode", fs.readFileSync(process.argv[1], "utf8"));' "$PROJECT_DIR/Sources/FeishuReader.js"
node "$PROJECT_DIR/Tests/WorkspaceNavigationTests.cjs"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/LiveJobData.swift" "$PROJECT_DIR/Tests/LiveJobDataTests.swift" -o "$TEST_DIR/LiveJobDataTests"
FIXTURE="$PROJECT_DIR/../../方案设计/验证样本/飞书公开读取-2026-11-17/feishu-public-full.tsv"
if [[ -f "$FIXTURE" ]]; then "$TEST_DIR/LiveJobDataTests" "$FIXTURE"; else "$TEST_DIR/LiveJobDataTests"; fi
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Tests/ConnectorTests.swift" -o "$TEST_DIR/ConnectorTests"
"$TEST_DIR/ConnectorTests" "$PROJECT_DIR/Sources/BossExtractor.js"
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Sources/ArkAI.swift" "$PROJECT_DIR/Sources/JobGreetingDraft.swift" "$PROJECT_DIR/Tests/ChatTests.swift" -o "$TEST_DIR/ChatTests"
"$TEST_DIR/ChatTests" "$PROJECT_DIR/Sources/BossChat.js"

swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Sources/ArkAI.swift" "$PROJECT_DIR/Sources/CareerChatStream.swift" "$PROJECT_DIR/Tests/CareerChatStreamTests.swift" -o "$TEST_DIR/CareerChatStreamTests"
"$TEST_DIR/CareerChatStreamTests"
swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Sources/ArkAI.swift" "$PROJECT_DIR/Sources/FlowIntent.swift" "$PROJECT_DIR/Sources/CareerChatArchive.swift" "$PROJECT_DIR/Tests/CareerChatArchiveTests.swift" -o "$TEST_DIR/CareerChatArchiveTests"
"$TEST_DIR/CareerChatArchiveTests"

swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/LiveJobData.swift" "$PROJECT_DIR/Sources/LiveJobFilters.swift" "$PROJECT_DIR/Tests/LiveJobFilterTests.swift" -o "$TEST_DIR/LiveJobFilterTests"
if [[ -f "$FIXTURE" ]]; then "$TEST_DIR/LiveJobFilterTests" "$FIXTURE"; else "$TEST_DIR/LiveJobFilterTests"; fi
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Sources/ArkAI.swift" "$PROJECT_DIR/Sources/ApplicationProfile.swift" "$PROJECT_DIR/Sources/ApplicationResumeParser.swift" "$PROJECT_DIR/Tests/ApplicationProfileTests.swift" -o "$TEST_DIR/ApplicationProfileTests"
"$TEST_DIR/ApplicationProfileTests"
node -e 'const fs=require("fs");const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;new AsyncFunction("action","token","assignments","desiredSections",fs.readFileSync(process.argv[1],"utf8"));' "$PROJECT_DIR/Sources/ApplicationAutofill.js"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Sources/ArkAI.swift" "$PROJECT_DIR/Sources/ApplicationProfile.swift" "$PROJECT_DIR/Sources/ApplicationAutofill.swift" "$PROJECT_DIR/Tests/ApplicationAutofillTests.swift" -o "$TEST_DIR/ApplicationAutofillTests"
"$TEST_DIR/ApplicationAutofillTests" "$PROJECT_DIR"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Sources/ArkAI.swift" "$PROJECT_DIR/Sources/ApplicationProfile.swift" "$PROJECT_DIR/Sources/ApplicationAutofill.swift" "$PROJECT_DIR/Tests/ApplicationMatchingTests.swift" -o "$TEST_DIR/ApplicationMatchingTests"
"$TEST_DIR/ApplicationMatchingTests"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Tests/ApplicationIdentityDOMTests.swift" -o "$TEST_DIR/ApplicationIdentityDOMTests"
"$TEST_DIR/ApplicationIdentityDOMTests" "$PROJECT_DIR"

node -e 'new (Object.getPrototypeOf(async function(){}).constructor)("mode",require("fs").readFileSync(process.argv[1],"utf8"));' "$PROJECT_DIR/Sources/XiaohongshuReader.js"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/BossTypes.swift" "$PROJECT_DIR/Sources/ArkAI.swift" "$PROJECT_DIR/Sources/ApplicationProfile.swift" "$PROJECT_DIR/Sources/FlowCompanyRole.swift" "$PROJECT_DIR/Sources/InterviewData.swift" "$PROJECT_DIR/Sources/InterviewAI.swift" "$PROJECT_DIR/Sources/InterviewCollection.swift" "$PROJECT_DIR/Tests/InterviewTests.swift" -o "$TEST_DIR/InterviewTests"
"$TEST_DIR/InterviewTests" "$PROJECT_DIR"
