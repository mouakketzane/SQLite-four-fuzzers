#!/usr/bin/env bash
# build_all.sh
# Compiles all 12 fuzzer binaries across the four targets:
#   SQLite  — sqlite3_DDFuzzer, sqlite_wingfuzzer_real, sqlite_libfuzzer
#   RHash   — rhash_DDFuzzer,   rhash_wingfuzz_real,    rhash_libfuzzer
#   cJSON   — cjson_DDFuzzer,   cjson_wingfuzz_real,    cjson_libfuzzer
#   RE2     — re2_DDFuzzer,     re2_wingfuzz_real,       re2_libfuzzer
#
# Usage: ./build_all.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

run_build() {
    local script="$1"
    echo ""
    echo "################################################################"
    echo "  $script"
    echo "################################################################"
    bash "$REPO/$script"
}

run_build build_sqlite.sh
run_build build_rhash.sh
run_build build_cjson.sh
run_build build_re2.sh

echo ""
echo "================================================================"
echo "  Build summary"
echo "================================================================"

BINARIES=(
    sqlite3_DDFuzzer sqlite_wingfuzzer_real sqlite_libfuzzer
    rhash_DDFuzzer   rhash_wingfuzz_real    rhash_libfuzzer
    cjson_DDFuzzer   cjson_wingfuzz_real    cjson_libfuzzer
    re2_DDFuzzer     re2_wingfuzz_real      re2_libfuzzer
)

ok=0; fail=0
for bin in "${BINARIES[@]}"; do
    if [ -f "$REPO/$bin" ]; then
        printf "  [OK]   %s\n" "$bin"
        (( ok++ )) || true
    else
        printf "  [MISS] %s\n" "$bin"
        (( fail++ )) || true
    fi
done

echo ""
echo "  $ok / $((ok + fail)) binaries present"
[ "$fail" -eq 0 ] && echo "  All binaries compiled successfully." || echo "  WARNING: $fail binary/binaries missing (DDFuzz skipped without afl-clang-fast)."
