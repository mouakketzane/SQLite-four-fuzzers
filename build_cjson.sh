#!/usr/bin/env bash
# build_cjson.sh
# Builds LibFuzzer, WingFuzz, and DDFuzz binaries targeting cJSON.
#
# Usage: ./build_cjson.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$REPO/test_targets/cjson"
BUILD="$REPO/build"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v clang   &>/dev/null || die "clang not found"
command -v clang++ &>/dev/null || die "clang++ not found"

echo "=== Building LibFuzzer binary for cJSON ==="
clang -g -O2 -fsanitize=fuzzer,address \
    -I"$TARGET" \
    "$TARGET/cjson_harness.c" \
    "$TARGET/cJSON.c" \
    -o "$REPO/cjson_libfuzzer"
echo "  -> cjson_libfuzzer"

echo ""
echo "=== Building WingFuzz binary for cJSON ==="
clang -g -O2 -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping \
    -I"$TARGET" \
    -c "$TARGET/cjson_harness.c" -o "$BUILD/cjson_harness.o"

clang -g -O2 -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping \
    -I"$TARGET" \
    -c "$TARGET/cJSON.c" -o "$BUILD/cJSON_wf.o"

clang++ -g -O2 -fsanitize=address -no-pie \
    -fprofile-instr-generate -fcoverage-mapping \
    "$BUILD/cjson_harness.o" "$BUILD/cJSON_wf.o" \
    -Xlinker --start-group \
        "$BUILD/src/wingfuzz/libwingfuzz_main.a" \
        "$BUILD/src/wingfuzz/libwingfuzz_static.a" \
    -Xlinker --end-group \
    -lpthread -ldl \
    -o "$REPO/cjson_wingfuzz_real"
echo "  -> cjson_wingfuzz_real"

echo ""
echo "=== Building DDFuzz binary for cJSON ==="
if command -v afl-clang-fast &>/dev/null; then
    DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic \
    afl-clang-fast -g -O2 \
        -I"$TARGET" \
        "$TARGET/cjson_harness.c" \
        "$TARGET/cJSON.c" \
        /usr/local/lib/afl/libAFLDriver.a \
        -o "$REPO/cjson_DDFuzzer" -ldl
    echo "  -> cjson_DDFuzzer"
elif docker image inspect ddfuzz:local &>/dev/null; then
    echo "  Building inside ddfuzz:local..."
    docker run --rm \
        -v "$REPO:/workspaces/CyberSecurity" \
        ddfuzz:local \
        bash -c "
            DDG_INSTR=1 AFL_LLVM_INSTRUMENT=classic afl-clang-fast -g -O2 \
              -I /workspaces/CyberSecurity/test_targets/cjson \
              /workspaces/CyberSecurity/test_targets/cjson/cjson_harness.c \
              /workspaces/CyberSecurity/test_targets/cjson/cJSON.c \
              /usr/local/lib/afl/libAFLDriver.a \
              -o /workspaces/CyberSecurity/cjson_DDFuzzer -ldl
        "
    echo "  -> cjson_DDFuzzer"
else
    echo "  (skipped — neither afl-clang-fast nor ddfuzz:local Docker image found)"
fi

echo ""
echo "Done. Run ./benchmark_cjson.sh to start fuzzing."
