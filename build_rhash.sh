#!/usr/bin/env bash
# build_rhash.sh
# Builds LibFuzzer, WingFuzz, and DDFuzz binaries targeting RHash.
#
# Requires: clang, clang++ and the pre-built WingFuzz libraries in prebuilt/wingfuzz/
#
# Usage: ./build_rhash.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$REPO/test_targets/RHash"
BUILD="$REPO/build"
PREBUILT="$REPO/prebuilt/wingfuzz"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v clang    &>/dev/null || die "clang not found"
command -v clang++  &>/dev/null || die "clang++ not found"
[ -f "$TARGET/librhash/rhash.h" ] || die "RHash source not found in $TARGET — clone https://github.com/rhash/RHash first"
[ -f "$TARGET/rhash_harness.c"  ] || die "rhash_harness.c not found in $TARGET"
[ -f "$PREBUILT/libwingfuzz_main.a"   ] || die "prebuilt/wingfuzz/libwingfuzz_main.a not found"
[ -f "$PREBUILT/libwingfuzz_static.a" ] || die "prebuilt/wingfuzz/libwingfuzz_static.a not found"

mkdir -p "$BUILD"

# Generate config.mak (only needed once; safe to re-run)
cd "$TARGET"
./configure --cc=clang

# ─── LibFuzzer ────────────────────────────────────────────────────────────────
echo "=== Building LibFuzzer binary for RHash ==="
cd "$TARGET/librhash"
rm -f ./*.o librhash.a
make CC="clang -fsanitize=fuzzer-no-link,address -O2 -g" CFLAGS="" lib-static
cd "$REPO"
clang -g -O2 -fsanitize=fuzzer,address \
    -I"$TARGET" \
    "$TARGET/rhash_harness.c" \
    "$TARGET/librhash/librhash.a" \
    -o rhash_libfuzzer -ldl
echo "  -> rhash_libfuzzer"

# ─── WingFuzz ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Building WingFuzz binary for RHash ==="
cd "$TARGET/librhash"
rm -f ./*.o librhash.a
make CC="clang -fsanitize=fuzzer-no-link,address -fprofile-instr-generate -fcoverage-mapping -O2 -g" CFLAGS="" lib-static
cd "$REPO"

clang -g -O2 -fsanitize=fuzzer-no-link \
    -fprofile-instr-generate -fcoverage-mapping \
    -I"$TARGET" \
    -c "$TARGET/rhash_harness.c" \
    -o "$BUILD/rhash_harness.o"

clang++ -O2 -g -fsanitize=address -no-pie \
    -fprofile-instr-generate -fcoverage-mapping \
    "$BUILD/rhash_harness.o" \
    "$TARGET/librhash/librhash.a" \
    -Xlinker --start-group \
        "$PREBUILT/libwingfuzz_main.a" \
        "$PREBUILT/libwingfuzz_static.a" \
    -Xlinker --end-group \
    -lpthread -ldl \
    -o rhash_wingfuzz_real
echo "  -> rhash_wingfuzz_real"

# ─── DDFuzz ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Building DDFuzz binary for RHash ==="
if command -v afl-clang-fast &>/dev/null; then
    cd "$TARGET/librhash"
    rm -f ./*.o librhash.a
    DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
        make CC="afl-clang-fast -O2 -g" CFLAGS="" lib-static
    cd "$REPO"
    DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
        afl-clang-fast -g -O2 \
        -I"$TARGET" \
        "$TARGET/rhash_harness.c" \
        "$TARGET/librhash/librhash.a" \
        /usr/local/lib/afl/libAFLDriver.a \
        -o rhash_DDFuzzer -ldl
    echo "  -> rhash_DDFuzzer"
elif docker image inspect ddfuzz:local &>/dev/null 2>&1; then
    echo "  Building RHash DDFuzz binary inside ddfuzz:local..."
    docker run --rm \
        -v "$REPO:/workspaces/CyberSecurity" \
        ddfuzz:local \
        bash -c "
            set -e
            cd /workspaces/CyberSecurity/test_targets/RHash/librhash
            rm -f ./*.o librhash.a
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
                make CC='afl-clang-fast -O2 -g' CFLAGS='' lib-static
            cd /workspaces/CyberSecurity
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic afl-clang-fast -g -O2 \
                -I /workspaces/CyberSecurity/test_targets/RHash \
                /workspaces/CyberSecurity/test_targets/RHash/rhash_harness.c \
                /workspaces/CyberSecurity/test_targets/RHash/librhash/librhash.a \
                /usr/local/lib/afl/libAFLDriver.a \
                -o /workspaces/CyberSecurity/rhash_DDFuzzer -ldl
        "
    echo "  -> rhash_DDFuzzer"
else
    echo "  (skipped — neither afl-clang-fast nor ddfuzz:local Docker image found)"
fi

echo ""
echo "Done. Run ./benchmark_rhash.sh to start fuzzing."
