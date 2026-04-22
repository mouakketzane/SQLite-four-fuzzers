#!/usr/bin/env bash
# build_re2.sh
# Builds LibFuzzer, WingFuzz, and DDFuzz binaries targeting re2.
#
# Requires: libre2-dev (pkg-config re2 must work)
#
# Usage: ./build_re2.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$REPO/test_targets/re2"
BUILD="$REPO/build"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v clang++ &>/dev/null || die "clang++ not found"
pkg-config --exists re2       || die "re2 not found via pkg-config — install libre2-dev"

RE2_CFLAGS=$(pkg-config --cflags re2)
RE2_LIBS=$(pkg-config --libs re2)

echo "=== Building LibFuzzer binary for re2 ==="
# shellcheck disable=SC2086
clang++ -g -O2 -fsanitize=fuzzer,address \
    $RE2_CFLAGS \
    "$TARGET/re2_harness.cc" \
    -o "$REPO/re2_libfuzzer" \
    $RE2_LIBS -lpthread
echo "  -> re2_libfuzzer"

echo ""
echo "=== Building WingFuzz binary for re2 ==="
# shellcheck disable=SC2086
clang++ -g -O2 -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping \
    $RE2_CFLAGS \
    -c "$TARGET/re2_harness.cc" -o "$BUILD/re2_harness.o"

# shellcheck disable=SC2086
clang++ -g -O2 -fsanitize=address -no-pie \
    -fprofile-instr-generate -fcoverage-mapping \
    "$BUILD/re2_harness.o" \
    -Xlinker --start-group \
        "$BUILD/src/wingfuzz/libwingfuzz_main.a" \
        "$BUILD/src/wingfuzz/libwingfuzz_static.a" \
    -Xlinker --end-group \
    $RE2_LIBS -lpthread -ldl \
    -o "$REPO/re2_wingfuzz_real"
echo "  -> re2_wingfuzz_real"

echo ""
echo "=== Building DDFuzz binary for re2 ==="
if command -v afl-clang-fast++ &>/dev/null; then
    DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
    afl-clang-fast++ -g -O2 \
        -I"$TARGET/re2_src" \
        "$TARGET/re2_harness.cc" \
        "$TARGET/re2_src/obj/libre2.a" \
        /usr/local/lib/afl/libAFLDriver.a \
        -lpthread -o "$REPO/re2_DDFuzzer"
    echo "  -> re2_DDFuzzer"
elif docker image inspect ddfuzz:local &>/dev/null; then
    echo "  Building re2 from vendored source inside ddfuzz:local..."
    docker run --rm \
        -v "$REPO:/workspaces/CyberSecurity" \
        ddfuzz:local \
        bash -c "
            set -e
            cd /workspaces/CyberSecurity/test_targets/re2/re2_src
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
              make -j\$(nproc) CXX=afl-clang-fast++ CC=afl-clang-fast \
              CXXFLAGS='-O2 -g -fPIC' obj/libre2.a
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic afl-clang-fast++ -g -O2 \
              -I /workspaces/CyberSecurity/test_targets/re2/re2_src \
              /workspaces/CyberSecurity/test_targets/re2/re2_harness.cc \
              /workspaces/CyberSecurity/test_targets/re2/re2_src/obj/libre2.a \
              /usr/local/lib/afl/libAFLDriver.a \
              -lpthread -o /workspaces/CyberSecurity/re2_DDFuzzer
        "
    echo "  -> re2_DDFuzzer"
else
    echo "  (skipped — neither afl-clang-fast++ nor ddfuzz:local Docker image found)"
fi

echo ""
echo "Done. Run ./benchmark_re2.sh to start fuzzing."
