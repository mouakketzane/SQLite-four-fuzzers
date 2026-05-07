#!/usr/bin/env bash
# Scan a crash directory and report the first time each injected bug was triggered.
# Usage: scan_crashes.sh <crash_dir> <start_epoch_secs> <replay_binary> <target>
#   target: one of cjson rhash re2 sqlite
# Prints a comma-separated string like "BUG_C1:42,BUG_C2:not_found"

set -uo pipefail

CRASH_DIR="${1:-}"
START_EPOCH="${2:-0}"
BINARY="${3:-}"
TARGET="${4:-unknown}"
LOG_FILE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IDENTIFY="$SCRIPT_DIR/identify_bug.sh"

# Known bugs per target (space-separated bug IDs)
case "$TARGET" in
    cjson)  KNOWN_BUGS="BUG_C1 BUG_C2" ;;
    rhash)  KNOWN_BUGS="BUG_R1 BUG_R2" ;;
    re2)    KNOWN_BUGS="BUG_RE1" ;;
    sqlite) KNOWN_BUGS="BUG_S1 BUG_S2" ;;
    *)      KNOWN_BUGS="" ;;
esac

# Associative map: bug_id -> earliest elapsed seconds
declare -A first_seen

if [ -d "$CRASH_DIR" ] && [ -x "$IDENTIFY" ] && [ -f "$BINARY" ]; then
    while IFS= read -r -d '' crash_file; do
        # Get file modification time (Linux: stat --printf; fallback: stat -f)
        mtime=$(stat --printf="%Y" "$crash_file" 2>/dev/null \
                || stat -f "%m"    "$crash_file" 2>/dev/null \
                || echo "0")
        elapsed=$(( mtime - START_EPOCH ))
        [ "$elapsed" -lt 0 ] && elapsed=0

        bug_id=$("$IDENTIFY" "$crash_file" "$BINARY" 2>/dev/null || echo "UNKNOWN")

        if [ "$bug_id" != "UNKNOWN" ] && [ -n "$bug_id" ]; then
            if [ -z "${first_seen[$bug_id]+_}" ] || [ "$elapsed" -lt "${first_seen[$bug_id]}" ]; then
                first_seen[$bug_id]=$elapsed
            fi
        fi
    done < <(find "$CRASH_DIR" -maxdepth 1 \
                  \( -name "crash-*" -o -name "id:*,sig:*" \) \
                  -type f -print0 2>/dev/null)
fi

# Also scan a fuzzer log file for inline ASAN crashes (used for fuzzers like
# WingFuzz that don't write crash artifact files).
if [ -f "${LOG_FILE}" ]; then
    log_mtime=$(stat --printf="%Y" "$LOG_FILE" 2>/dev/null \
                || stat -f "%m"    "$LOG_FILE" 2>/dev/null \
                || echo "0")
    log_elapsed=$(( log_mtime - START_EPOCH ))
    [ "$log_elapsed" -lt 0 ] && log_elapsed=0

    log_bug="UNKNOWN"
    if   grep -qE "in parse_string"         "$LOG_FILE" 2>/dev/null; then log_bug="BUG_C1"
    elif grep -qE "in print_string_ptr"      "$LOG_FILE" 2>/dev/null; then log_bug="BUG_C2"
    elif grep -qE "in rhash_md5_update"      "$LOG_FILE" 2>/dev/null; then log_bug="BUG_R1"
    elif grep -qE "in rhash_sha1_final"      "$LOG_FILE" 2>/dev/null; then log_bug="BUG_R2"
    elif grep -qE "AllocInst"                "$LOG_FILE" 2>/dev/null; then log_bug="BUG_RE1"
    elif grep -qE "sqlite3CheckIdentifier"   "$LOG_FILE" 2>/dev/null; then log_bug="BUG_S1"
    elif grep -qE "sqlite3CopyWindowKeyword" "$LOG_FILE" 2>/dev/null; then log_bug="BUG_S2"
    fi

    if [ "$log_bug" != "UNKNOWN" ]; then
        if [ -z "${first_seen[$log_bug]+_}" ] || [ "$log_elapsed" -lt "${first_seen[$log_bug]}" ]; then
            first_seen[$log_bug]=$log_elapsed
        fi
    fi
fi

# Build output string: all known bugs with their first-seen time or "not_found"
result=""
for bug_id in $KNOWN_BUGS; do
    time_val="${first_seen[$bug_id]:-not_found}"
    if [ -n "$result" ]; then result="${result},"; fi
    result="${result}${bug_id}:${time_val}"
done

if [ -z "$result" ]; then
    echo "none"
else
    echo "$result"
fi
