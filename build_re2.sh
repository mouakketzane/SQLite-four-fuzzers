#!/usr/bin/env bash
# build_re2.sh
# Builds LibFuzzer, WingFuzz, and DDFuzz binaries targeting re2.
#
# Requires: clang++, make; uses vendored re2_src (NOT system re2) so the injected bug is present
#
# Usage: ./build_re2.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$REPO/test_targets/re2"
BUILD="$REPO/build"
PREBUILT="$REPO/prebuilt/wingfuzz"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v clang++ &>/dev/null || die "clang++ not found"
[ -d "$TARGET/re2_src" ]              || die "test_targets/re2/re2_src not found"
[ -f "$PREBUILT/libwingfuzz_main.a"   ] || die "prebuilt/wingfuzz/libwingfuzz_main.a not found"
[ -f "$PREBUILT/libwingfuzz_static.a" ] || die "prebuilt/wingfuzz/libwingfuzz_static.a not found"

# ─── Pre-clean root-owned artifacts from prior Docker builds ─────────────────
if [ -n "$(find "$TARGET/re2_src" -maxdepth 2 ! -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
    echo "  (root-owned files detected in re2_src — cleaning via Docker)"
    docker run --rm \
        -v "$REPO:/workspaces/CyberSecurity" \
        ddfuzz:local \
        bash -c "rm -rf /workspaces/CyberSecurity/test_targets/re2/re2_src/obj"
fi

# Build the vendored re2 source (which has BUG_RE1) with ASAN.
# Both LibFuzzer and WingFuzz link against this so the injected bug is present.
echo "=== Building vendored re2 with ASAN ==="
cd "$TARGET/re2_src"
make clean 2>/dev/null || true
make -j"$(nproc)" CXX=clang++ CC=clang \
    CXXFLAGS="-O2 -g -fPIC -fsanitize=address" \
    obj/libre2.a
cd "$REPO"
echo "  -> $TARGET/re2_src/obj/libre2.a (ASAN)"

echo ""
echo "=== Building LibFuzzer binary for re2 ==="
clang++ -g -O2 -fsanitize=fuzzer,address \
    -I"$TARGET/re2_src" \
    "$TARGET/re2_harness.cc" \
    "$TARGET/re2_src/obj/libre2.a" \
    -o "$REPO/re2_libfuzzer" \
    -lpthread
echo "  -> re2_libfuzzer"

echo ""
echo "=== Building WingFuzz binary for re2 ==="
clang++ -g -O2 -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping \
    -I"$TARGET/re2_src" \
    -c "$TARGET/re2_harness.cc" -o "$BUILD/re2_harness.o"

clang++ -g -O2 -fsanitize=address -no-pie \
    -fprofile-instr-generate -fcoverage-mapping \
    "$BUILD/re2_harness.o" \
    -Xlinker --start-group \
        "$PREBUILT/libwingfuzz_main.a" \
        "$PREBUILT/libwingfuzz_static.a" \
    -Xlinker --end-group \
    "$TARGET/re2_src/obj/libre2.a" \
    -lpthread -ldl \
    -o "$REPO/re2_wingfuzz_real"
echo "  -> re2_wingfuzz_real"

echo ""
echo "=== Building DDFuzz binary for re2 ==="
if command -v afl-clang-fast++ &>/dev/null; then
    cd "$TARGET/re2_src"
    make clean 2>/dev/null || true
    DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
    make -j"$(nproc)" CXX=afl-clang-fast++ CC=afl-clang-fast \
        CXXFLAGS='-O2 -g -fPIC' obj/libre2.a
    cd "$REPO"
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
            make clean 2>/dev/null || true
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
              make -j\$(nproc) CXX=afl-clang-fast++ CC=afl-clang-fast \
              CXXFLAGS='-O2 -g -fPIC' obj/libre2.a
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic afl-clang-fast++ -g -O2 \
              -I /workspaces/CyberSecurity/test_targets/re2/re2_src \
              /workspaces/CyberSecurity/test_targets/re2/re2_harness.cc \
              /workspaces/CyberSecurity/test_targets/re2/re2_src/obj/libre2.a \
              /usr/local/lib/afl/libAFLDriver.a \
              -lpthread -o /workspaces/CyberSecurity/re2_DDFuzzer
            rm -rf /workspaces/CyberSecurity/test_targets/re2/re2_src/obj
        "
    echo "  -> re2_DDFuzzer"
else
    echo "  (skipped — neither afl-clang-fast++ nor ddfuzz:local Docker image found)"
fi

echo ""
echo "Done. Run ./benchmark_re2.sh to start fuzzing."
