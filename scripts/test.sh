#!/bin/bash
# Compiles the pure-logic sources together with the assert-based test runner
# and executes it. XCTest needs full Xcode; this works with Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
swiftc -O \
    Sources/MacPulse/GitHubParser.swift \
    Sources/MacPulse/ProcessParser.swift \
    Sources/MacPulse/FileScanner.swift \
    Sources/MacPulse/BackupStatus.swift \
    Sources/MacPulse/ImprovementsEngine.swift \
    Sources/MacPulse/SecurityAudit.swift \
    Sources/MacPulse/Shell.swift \
    Sources/MacPulse/Formatters.swift \
    Sources/MacPulse/ClaudeUsageParser.swift \
    Tests/TestRunner/main.swift \
    -o .build/testrunner

.build/testrunner
