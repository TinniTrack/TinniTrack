#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Project: $PROJECT_ROOT"
echo

echo "Xcode:"
xcodebuild -version
echo

echo "Booted simulators:"
xcrun simctl list devices booted
echo

echo "Active Xcode/test processes:"
pgrep -fl "/usr/bin/xcodebuild|/usr/bin/simctl|/usr/bin/xctest|/Developer/usr/bin/xctest" || true
echo

echo "XcodeBuildMCP processes:"
pgrep -fl "xcodebuildmcp" || true
echo

echo "Project root attributes:"
ls -lde@ "$PROJECT_ROOT"
xattr -l "$PROJECT_ROOT" 2>/dev/null || true
echo

echo "ResearchKit provenance sample:"
xattr -lr "$PROJECT_ROOT/Frameworks/ResearchKit" 2>/dev/null | head -40 || true
echo

echo "Codex shell temp-file attributes:"
temp_file="$(mktemp /tmp/tinnitrack-doctor.XXXXXX)"
printf test > "$temp_file"
ls -l@ "$temp_file"
xattr -l "$temp_file" 2>/dev/null || true
rm -f "$temp_file"
