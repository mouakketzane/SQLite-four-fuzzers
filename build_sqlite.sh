#!/usr/bin/env bash
# build_sqlite.sh
# Builds LibFuzzer, WingFuzz, and DDFuzz binaries targeting sqlite3_full.
# All three fuzzers use the same SQLite source so results are comparable.
#
# Requires: clang, clang++, and the pre-built WingFuzz libraries in prebuilt/wingfuzz/
#
# Usage: ./build_sqlite.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SQLITE_FULL="$REPO/test_targets/sqlite3_full"
HARNESS="$REPO/test_targets/sqlite/sqlite_harness.c"
BUILD="$REPO/build"
PREBUILT="$REPO/prebuilt/wingfuzz"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v clang   &>/dev/null || die "clang not found"
command -v clang++ &>/dev/null || die "clang++ not found"
[ -f "$PREBUILT/libwingfuzz_main.a"   ] || die "prebuilt/wingfuzz/libwingfuzz_main.a not found"
[ -f "$PREBUILT/libwingfuzz_static.a" ] || die "prebuilt/wingfuzz/libwingfuzz_static.a not found"

mkdir -p "$BUILD"

# ─── Pre-clean root-owned artifacts from prior Docker builds ─────────────────
# Docker runs as root, leaving .o files, tsrc/, and a reconfigured Makefile
# all owned by root. Use Docker itself to wipe them before the host builds.
docker_clean() {
    docker run --rm \
        -v "$REPO:/workspaces/CyberSecurity" \
        ddfuzz:local \
        bash -c "
            cd /workspaces/CyberSecurity/test_targets/sqlite3_full
            make clean 2>/dev/null || true
            rm -rf tsrc .target_source Makefile sqlite_cfg.h sqlite3.pc
        "
}

if [ -n "$(find "$SQLITE_FULL" -maxdepth 1 ! -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
    echo "  (root-owned files detected in sqlite3_full — cleaning via Docker)"
    docker_clean
fi

# ─── LibFuzzer ────────────────────────────────────────────────────────────────
echo "=== Building LibFuzzer binary for SQLite ==="
cd "$SQLITE_FULL"
make clean 2>/dev/null || true
cp "$SQLITE_FULL/tool/lempar.c" "$SQLITE_FULL/"
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
echo "  -> sqlite_libfuzzer"

# ─── WingFuzz ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Building WingFuzz binary for SQLite ==="
cd "$SQLITE_FULL"
make clean 2>/dev/null || true
cp "$SQLITE_FULL/tool/lempar.c" "$SQLITE_FULL/"
CC="clang -fsanitize=fuzzer-no-link,address -fprofile-instr-generate -fcoverage-mapping -O2 -g" \
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
echo "  -> sqlite_wingfuzzer_real"

# ─── DDFuzz ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Building DDFuzz binary for SQLite ==="
if command -v afl-clang-fast &>/dev/null; then
    cd "$SQLITE_FULL"
    make clean 2>/dev/null || true
    cp "$SQLITE_FULL/tool/lempar.c" "$SQLITE_FULL/"
    DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
      CC=afl-clang-fast \
      ./configure --enable-static --disable-shared --disable-amalgamation
    make -j"$(nproc)"
    cd "$REPO"
    DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
      afl-clang-fast -g -O2 \
      -I"$SQLITE_FULL" \
      "$HARNESS" \
      "$SQLITE_FULL/libsqlite3.a" \
      /usr/local/lib/afl/libAFLDriver.a \
      -o sqlite3_DDFuzzer -ldl -lpthread -lm
    echo "  -> sqlite3_DDFuzzer"
elif docker image inspect ddfuzz:local &>/dev/null 2>&1; then
    echo "  Building SQLite DDFuzz binary inside ddfuzz:local..."
    docker run --rm \
        -v "$REPO:/workspaces/CyberSecurity" \
        ddfuzz:local \
        bash -c "
            set -e
            cd /workspaces/CyberSecurity/test_targets/sqlite3_full
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
              CC=afl-clang-fast \
              ./configure --enable-static --disable-shared --disable-amalgamation
            make clean
            cp tool/lempar.c .
            make -j\$(nproc)
            cd /workspaces/CyberSecurity
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic afl-clang-fast -g -O2 \
              -I /workspaces/CyberSecurity/test_targets/sqlite3_full \
              /workspaces/CyberSecurity/test_targets/sqlite/sqlite_harness.c \
              /workspaces/CyberSecurity/test_targets/sqlite3_full/libsqlite3.a \
              /usr/local/lib/afl/libAFLDriver.a \
              -o /workspaces/CyberSecurity/sqlite3_DDFuzzer -ldl -lpthread -lm
            cd /workspaces/CyberSecurity/test_targets/sqlite3_full
            make clean
            rm -f Makefile sqlite_cfg.h sqlite3.pc
        "
    echo "  -> sqlite3_DDFuzzer"
else
    echo "  (skipped — neither afl-clang-fast nor ddfuzz:local Docker image found)"
fi

echo ""
echo "Done. Run ./benchmark_sqlite.sh to start fuzzing."
