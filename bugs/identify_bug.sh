#!/usr/bin/env bash
# Replay a crash file against a fuzzer binary and identify which injected bug triggered.
# Usage: identify_bug.sh <crash_file> <binary>
# Prints one of: BUG_C1 BUG_C2 BUG_R1 BUG_R2 BUG_RE1 BUG_S1 BUG_S2 UNKNOWN

set -uo pipefail

CRASH="$1"
BINARY="$2"

if [ ! -f "$CRASH" ] || [ ! -f "$BINARY" ]; then
    echo "UNKNOWN"
    exit 0
fi

# LibFuzzer-style binaries accept a crash file as a positional argument.
# ASAN stack traces go to stderr; we merge to capture them.
ASAN_OUT=$(timeout 15 "$BINARY" "$CRASH" 2>&1 </dev/null || true)

# Match ASAN stack trace frames to known injected bug function names.
if   echo "$ASAN_OUT" | grep -qE "in parse_string"; then
    echo "BUG_C1"
elif echo "$ASAN_OUT" | grep -qE "in print_string_ptr"; then
    echo "BUG_C2"
elif echo "$ASAN_OUT" | grep -qE "in rhash_md5_update"; then
    echo "BUG_R1"
elif echo "$ASAN_OUT" | grep -qE "in rhash_sha1_final"; then
    echo "BUG_R2"
elif echo "$ASAN_OUT" | grep -qE "AllocInst"; then
    echo "BUG_RE1"
elif echo "$ASAN_OUT" | grep -qE "sqlite3CheckIdentifier"; then
    echo "BUG_S1"
elif echo "$ASAN_OUT" | grep -qE "sqlite3CopyWindowKeyword"; then
    echo "BUG_S2"
else
    echo "UNKNOWN"
fi
