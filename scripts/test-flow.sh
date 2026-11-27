#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TEST_DIR=$(mktemp -d /tmp/offerflow-flow-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
common=(Sources/Models.swift Sources/BossTypes.swift Sources/ArkAI.swift Sources/ApplicationProfile.swift)
swiftc -parse-as-library -target arm64-apple-macosx14.0 $common Sources/ApplicationResumeParser.swift Sources/LiveJobData.swift Sources/ApplicationTracking.swift Sources/FlowIntent.swift Sources/CandidateMaterials.swift Sources/FlowCalendarProjection.swift Sources/BossBatchModels.swift Tests/FlowJourneyTests.swift -o "$TEST_DIR/FlowJourneyTests"
"$TEST_DIR/FlowJourneyTests"
swiftc -parse-as-library -target arm64-apple-macosx14.0 $common Sources/FlowCompanyRole.swift Sources/InterviewData.swift Sources/CoachSources.swift Tests/CoachSourcesTests.swift -o "$TEST_DIR/CoachSourcesTests"
"$TEST_DIR/CoachSourcesTests"
swiftc -parse-as-library -target arm64-apple-macosx14.0 Sources/OfferFlowTheme.swift Sources/ApplicationBrowserControls.swift Sources/WorkspaceTabs.swift Tests/WorkspaceTabsTests.swift -o "$TEST_DIR/WorkspaceTabsTests"
"$TEST_DIR/WorkspaceTabsTests"
