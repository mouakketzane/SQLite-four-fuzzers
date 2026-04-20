#!/usr/bin/env bash
# Usage: ./run_fuzzers.sh <fuzzer> <target> [duration_seconds]
#   fuzzer:   libfuzzer | wingfuzz | ddfuzz
#   target:   sqlite | rhash
#   duration: optional, default 60 (seconds)
#
# Examples:
#   ./run_fuzzers.sh libfuzzer sqlite
#   ./run_fuzzers.sh ddfuzz rhash 120
#
# Prerequisites:
#   - Binaries must already be built (see README.md or BUILD COMMANDS below)
#   - Docker must be running (required for ddfuzz)
#   - Run from the repo root: /path/to/CyberSecurity/

set -e
FUZZER="${1}"
TARGET="${2}"
DURATION="${3:-60}"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: $0 <libfuzzer|wingfuzz|ddfuzz> <sqlite|rhash> [duration_seconds]"
  exit 1
}

[ -z "$FUZZER" ] || [ -z "$TARGET" ] && usage

# ---------------------------------------------------------------------------
# libFuzzer
# ---------------------------------------------------------------------------
# Build sqlite (run build_comparable.sh inside devcontainer):
#   ./build_comparable.sh
#
# Build rhash:
#   cd test_targets/RHash/librhash && rm -f *.o librhash.a
#   make CC="clang -fsanitize=fuzzer-no-link,address -g" CFLAGS="-O2" lib-static
#   cd <repo_root>
#   clang++ -g -O2 -fsanitize=fuzzer,address \
#     test_targets/RHash/rhash_harness.c test_targets/RHash/librhash/librhash.a \
#     -o rhash_libfuzzer
#
run_libfuzzer_sqlite() {
  echo "[libfuzzer] Fuzzing sqlite for ${DURATION}s..."
  cd "$WORKDIR"
  ./sqlite_libfuzzer sqlite_corpus/ -max_total_time="$DURATION"
}

run_libfuzzer_rhash() {
  echo "[libfuzzer] Fuzzing rhash for ${DURATION}s..."
  cd "$WORKDIR"
  ./rhash_libfuzzer rhash_corpus/ -max_total_time="$DURATION"
}

# ---------------------------------------------------------------------------
# WingFuzz  (libFuzzer fork with data-coverage tracking)
# ---------------------------------------------------------------------------
# Build sqlite (run build_comparable.sh inside devcontainer):
#   ./build_comparable.sh
#
# Build rhash (run inside wingfuzz devcontainer or with clang-13 installed):
#   mkdir build && cd build && cmake .. && make
#   cd test_targets/RHash/librhash && rm -f *.o librhash.a
#   make CC="clang-13 -O2 -g -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping" lib-static
#   cd <repo_root>
#   clang++-13 -O2 -g -fsanitize=fuzzer,address -fprofile-instr-generate -fcoverage-mapping \
#     /workspaces/CyberSecurity/build/src/wingfuzz/libwingfuzz_main.a \
#     /workspaces/CyberSecurity/build/src/wingfuzz/libwingfuzz_static.a \
#     /workspaces/CyberSecurity/build/rhash_harness.o \
#     /workspaces/CyberSecurity/test_targets/RHash/librhash/librhash.a \
#     -o rhash_wingfuzz_real
#
run_wingfuzz_sqlite() {
  echo "[wingfuzz] Fuzzing sqlite for ${DURATION}s..."
  cd "$WORKDIR"
  LLVM_PROFILE_FILE="coverage.profraw" ./sqlite_wingfuzzer_real sqlite_corpus/ -max_total_time="$DURATION"
}

run_wingfuzz_rhash() {
  echo "[wingfuzz] Fuzzing rhash for ${DURATION}s..."
  cd "$WORKDIR"
  LLVM_PROFILE_FILE="coverage.profraw" ./rhash_wingfuzz_real rhash_corpus/ -max_total_time="$DURATION"
}

# ---------------------------------------------------------------------------
# DDFuzz  (AFL++ fork with Data Dependency Graph instrumentation)
# ---------------------------------------------------------------------------
# Requires Docker image: ddfuzz:local
# Build it once with:
#   docker build -f .devcontainer/DDFuzz/Dockerfile.DDFuzz -t ddfuzz:local .
#
# Build sqlite (run inside ddfuzz container):
#   export DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic
#   cd test_targets/sqlite3_full
#   CC=afl-clang-fast ./configure --enable-static --disable-shared --disable-amalgamation
#   make
#   afl-clang-fast -O2 -I. -fsanitize=fuzzer \
#     test_targets/sqlite/sqlite_harness.c \
#     test_targets/sqlite3_full/libsqlite3.a \
#     -o sqlite3_DDFuzzer -ldl -lpthread -lm
#
# Build rhash (run inside ddfuzz container):
#   export DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic
#   cd test_targets/RHash && make clean
#   CC=afl-clang-fast ./configure --enable-static && make
#   afl-clang-fast -O2 -I. -I./librhash -fsanitize=fuzzer \
#     rhash_harness.c ./librhash/librhash.a -o rhash_DDFuzzer -ldl
#
run_ddfuzz_sqlite() {
  echo "[ddfuzz] Fuzzing sqlite for ${DURATION}s (via Docker)..."
  mkdir -p "$WORKDIR/outputs/ddfuzz_sqlite"
  docker run --rm \
    -v "$WORKDIR:/workspaces/CyberSecurity" \
    -e AFL_SKIP_CPUFREQ=1 \
    -e AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    -e AFL_NO_UI=1 \
    --privileged \
    ddfuzz:local \
    bash -c "timeout $DURATION afl-fuzz \
      -i /workspaces/CyberSecurity/sqlite_corpus/ \
      -o /workspaces/CyberSecurity/outputs/ddfuzz_sqlite \
      -- /workspaces/CyberSecurity/sqlite3_DDFuzzer || true"
}

run_ddfuzz_rhash() {
  echo "[ddfuzz] Fuzzing rhash for ${DURATION}s (via Docker)..."
  mkdir -p "$WORKDIR/outputs/ddfuzz_rhash"
  docker run --rm \
    -v "$WORKDIR:/workspaces/CyberSecurity" \
    -e AFL_SKIP_CPUFREQ=1 \
    -e AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    -e AFL_NO_UI=1 \
    --privileged \
    ddfuzz:local \
    bash -c "timeout $DURATION afl-fuzz \
      -i /workspaces/CyberSecurity/rhash_corpus/ \
      -o /workspaces/CyberSecurity/outputs/ddfuzz_rhash \
      -- /workspaces/CyberSecurity/rhash_DDFuzzer || true"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${FUZZER}_${TARGET}" in
  libfuzzer_sqlite)  run_libfuzzer_sqlite ;;
  libfuzzer_rhash)   run_libfuzzer_rhash ;;
  wingfuzz_sqlite)   run_wingfuzz_sqlite ;;
  wingfuzz_rhash)    run_wingfuzz_rhash ;;
  ddfuzz_sqlite)     run_ddfuzz_sqlite ;;
  ddfuzz_rhash)      run_ddfuzz_rhash ;;
  *) echo "Unknown combination: $FUZZER + $TARGET"; usage ;;
esac
