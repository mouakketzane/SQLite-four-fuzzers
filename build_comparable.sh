#!/usr/bin/env bash
# Rebuilds LibFuzzer and WingFuzz against sqlite3_full/ so all three fuzzers
# target the same SQLite codebase (DDFuzz already uses sqlite3_full).
#
# Requires: clang, clang++, and the pre-built WingFuzz libraries in prebuilt/wingfuzz/
#
# Usage: ./build_comparable.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SQLITE_FULL="$REPO/test_targets/sqlite3_full"
HARNESS="$REPO/test_targets/sqlite/sqlite_harness.c"
BUILD="$REPO/build"
PREBUILT="$REPO/prebuilt/wingfuzz"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$PREBUILT/libwingfuzz_main.a"   ] || die "prebuilt/wingfuzz/libwingfuzz_main.a not found"
[ -f "$PREBUILT/libwingfuzz_static.a" ] || die "prebuilt/wingfuzz/libwingfuzz_static.a not found"

mkdir -p "$BUILD"

echo "=== Building LibFuzzer against sqlite3_full ==="
cd "$SQLITE_FULL"
make clean 2>/dev/null || true
CC="clang -fsanitize=fuzzer-no-link,address -O2 -g" \
  ./configure --enable-static --disable-shared --disable-amalgamation
make -j"$(nproc)"

cd "$REPO"
clang++ -g -O2 -fsanitize=fuzzer,address \
  -I"$SQLITE_FULL" \
  "$HARNESS" \
  "$SQLITE_FULL/libsqlite3.a" \
  -o sqlite_libfuzzer \
  -ldl -lpthread
echo "  -> sqlite_libfuzzer rebuilt against sqlite3_full"

echo ""
echo "=== Building WingFuzz against sqlite3_full ==="
cd "$SQLITE_FULL"
make clean 2>/dev/null || true
CC="clang -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping -O2 -g" \
  ./configure --enable-static --disable-shared --disable-amalgamation
make -j"$(nproc)"

cd "$REPO"
clang++ -O2 -g -fsanitize=fuzzer-no-link \
  -fprofile-instr-generate -fcoverage-mapping \
  -I"$SQLITE_FULL" \
  -c "$HARNESS" \
  -o "$BUILD/harness_full.o"

clang++ -O2 -g -fsanitize=address -no-pie \
  -fprofile-instr-generate -fcoverage-mapping \
  "$BUILD/harness_full.o" \
  "$SQLITE_FULL/libsqlite3.a" \
  -Xlinker --start-group \
    "$PREBUILT/libwingfuzz_main.a" \
    "$PREBUILT/libwingfuzz_static.a" \
  -Xlinker --end-group \
  -lpthread -ldl \
  -o sqlite_wingfuzzer_real
echo "  -> sqlite_wingfuzzer_real rebuilt against sqlite3_full"

echo ""
echo "=== Restoring sqlite3_full for DDFuzz ==="
if command -v afl-clang-fast &>/dev/null; then
    cd "$SQLITE_FULL"
    make clean
    export DDG_INSTR=1
    export AFL_LLVM_INSTRUMENT=classic
    CC=afl-clang-fast \
      ./configure --enable-static --disable-shared --disable-amalgamation
    make -j"$(nproc)"
    echo "  -> sqlite3_full restored with DDFuzz instrumentation"
else
    echo "  (skipped — afl-clang-fast not on host PATH; DDFuzz build will run inside Docker)"
fi

echo ""
echo "All three fuzzers now target the same sqlite3_full codebase."
echo "  sqlite_libfuzzer        (LibFuzzer)"
echo "  sqlite_wingfuzzer_real  (WingFuzz)"
echo "  sqlite3_DDFuzzer        (DDFuzz — built via Docker if afl-clang-fast unavailable)"
