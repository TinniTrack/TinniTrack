#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/TinniTrack.xcodeproj"
SCHEME="${TINNITRACK_SCHEME:-TinniTrack Development}"
CONFIGURATION="${TINNITRACK_CONFIGURATION:-Debug Development}"
SIMULATOR_ID="${TINNITRACK_SIMULATOR_ID:-7B054EF2-9CE8-418A-8CC0-E317AD5D7DED}"
DERIVED_DATA_PATH="${TINNITRACK_DERIVED_DATA:-/tmp/TinniTrackTerminalDerivedData}"
LOG_PATH="${TINNITRACK_XCODE_LOG:-/tmp/tinnitrack-xcode-test.log}"
STATUS_PATH="${TINNITRACK_XCODE_STATUS:-/tmp/tinnitrack-xcode-test.status}"
WAIT_SECONDS="${TINNITRACK_XCODE_WAIT_SECONDS:-600}"

usage() {
    cat <<USAGE
Usage: scripts/xcode-test-terminal.sh [xcodebuild test args...]

Runs xcodebuild from Terminal.app so macOS does not attach Codex-origin
provenance extended attributes to signed build products.

Environment overrides:
  TINNITRACK_SIMULATOR_ID       Default: $SIMULATOR_ID
  TINNITRACK_DERIVED_DATA       Default: $DERIVED_DATA_PATH
  TINNITRACK_XCODE_WAIT_SECONDS Default: $WAIT_SECONDS

Examples:
  scripts/xcode-test-terminal.sh \\
    -only-testing:TinniTrackTests/StudyConsentCatalogTests

  scripts/xcode-test-terminal.sh \\
    -only-testing:TinniTrackUITests/TinniTrackUITests/testStudyNo1DashboardOpensConsentLandingDirectly
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if ! command -v osascript >/dev/null 2>&1; then
    echo "osascript is required to launch Terminal.app" >&2
    exit 2
fi

rm -f "$LOG_PATH" "$STATUS_PATH"

quote_arg() {
    printf "%q" "$1"
}

command_parts=(
    "cd"
    "$(quote_arg "$PROJECT_ROOT")"
    "&&"
    "xcodebuild"
    "-project"
    "$(quote_arg "$PROJECT_PATH")"
    "-scheme"
    "$(quote_arg "$SCHEME")"
    "-configuration"
    "$(quote_arg "$CONFIGURATION")"
    "-destination"
    "$(quote_arg "platform=iOS Simulator,id=$SIMULATOR_ID")"
    "-derivedDataPath"
    "$(quote_arg "$DERIVED_DATA_PATH")"
)

for arg in "$@"; do
    command_parts+=("$(quote_arg "$arg")")
done

command_parts+=(
    "test"
    ">"
    "$(quote_arg "$LOG_PATH")"
    "2>&1"
    ";"
    "echo"
    '$?'
    ">"
    "$(quote_arg "$STATUS_PATH")"
    ";"
    "exit"
)

terminal_command="${command_parts[*]}"
TINNITRACK_TERMINAL_COMMAND="$terminal_command" osascript <<'APPLESCRIPT' >/dev/null
tell application "Terminal"
    do script (system attribute "TINNITRACK_TERMINAL_COMMAND")
end tell
APPLESCRIPT

for ((i = 0; i < WAIT_SECONDS; i++)); do
    if [[ -f "$STATUS_PATH" ]]; then
        status="$(cat "$STATUS_PATH")"
        tail -120 "$LOG_PATH" || true
        exit "$status"
    fi
    sleep 1
done

echo "Timed out waiting for xcodebuild after ${WAIT_SECONDS}s." >&2
echo "Log: $LOG_PATH" >&2
tail -120 "$LOG_PATH" 2>/dev/null || true
exit 124
