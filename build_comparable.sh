#!/usr/bin/env bash
# Rebuilds LibFuzzer and WingFuzz against sqlite3_full/ so all three fuzzers
# target the same SQLite codebase (DDFuzz already uses sqlite3_full).
#
# Run inside the devcontainer where clang, clang-13, and the wingfuzz build
# artifacts are available.
#
# Usage: ./build_comparable.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SQLITE_FULL="$REPO/test_targets/sqlite3_full"
HARNESS="$REPO/test_targets/sqlite/sqlite_harness.c"
BUILD="$REPO/build"

echo "=== Building LibFuzzer against sqlite3_full ==="
cd "$SQLITE_FULL"
make clean
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
make clean
CC="clang-13 -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping -O2 -g" \
  ./configure --enable-static --disable-shared --disable-amalgamation
make -j"$(nproc)"

cd "$REPO"
clang++-13 -O2 -g -fsanitize=fuzzer-no-link \
  -fprofile-instr-generate -fcoverage-mapping \
  -I"$SQLITE_FULL" \
  -c "$HARNESS" \
  -o "$BUILD/harness_full.o"

clang++-13 -O2 -g -fsanitize=address \
  -fprofile-instr-generate -fcoverage-mapping \
  "$BUILD/harness_full.o" \
  "$SQLITE_FULL/libsqlite3.a" \
  -Xlinker --start-group \
    "$BUILD/src/wingfuzz/libwingfuzz_main.a" \
    "$BUILD/src/wingfuzz/libwingfuzz_static.a" \
  -Xlinker --end-group \
  -lpthread -ldl \
  -o sqlite_wingfuzzer_real
echo "  -> sqlite_wingfuzzer_real rebuilt against sqlite3_full"

echo ""
echo "=== Restoring sqlite3_full for DDFuzz ==="
cd "$SQLITE_FULL"
make clean
export DDG_INSTR=1
export AFL_LLVM_INSTRUMENT=classic
CC=afl-clang-fast \
  ./configure --enable-static --disable-shared --disable-amalgamation
make -j"$(nproc)"
echo "  -> sqlite3_full restored with DDFuzz instrumentation"

echo ""
echo "All three fuzzers now target the same sqlite3_full codebase."
echo "  sqlite_libfuzzer        (LibFuzzer)"
echo "  sqlite_wingfuzzer_real  (WingFuzz)"
echo "  sqlite3_DDFuzzer        (DDFuzz — binary unchanged, library rebuilt)"
