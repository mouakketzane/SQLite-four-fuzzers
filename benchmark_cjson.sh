#!/usr/bin/env bash
# benchmark_cjson.sh
# Runs LibFuzzer, WingFuzz, and DDFuzz on cJSON for 60 seconds each,
# then measures and compares branch coverage, exec/s, corpus size, and crashes.
#
# Prerequisites: run build_cjson.sh first.
#
# Usage: ./benchmark_cjson.sh [duration_seconds]  (default: 60)

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DURATION="${1:-60}"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$REPO/results/benchmark_cjson_$RUN_ID"
SEEDS="$REPO/cjson_corpus"

LF_BIN="$REPO/cjson_libfuzzer"
WF_BIN="$REPO/cjson_wingfuzz_real"
DDF_BIN="/workspaces/CyberSecurity/cjson_DDFuzzer"
COV_BIN="$REPO/cjson_cov_replay"

CJSON_TARGET="$REPO/test_targets/cjson"

LLVM_PROFDATA="llvm-profdata"
LLVM_COV="llvm-cov"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

HAS_DDFUZZ=1
check_bins() {
    [ -f "$LF_BIN" ] || die "cjson_libfuzzer not found — run build_cjson.sh first"
    [ -f "$WF_BIN" ] || die "cjson_wingfuzz_real not found — run build_cjson.sh first"
    if [ ! -f "$REPO/cjson_DDFuzzer" ]; then
        echo "WARNING: cjson_DDFuzzer not found — DDFuzz step will be skipped"
        HAS_DDFUZZ=0
    fi
    if [ "$HAS_DDFUZZ" -eq 1 ]; then
        docker image inspect ddfuzz:local &>/dev/null || { echo "WARNING: Docker image ddfuzz:local not found — DDFuzz step will be skipped"; HAS_DDFUZZ=0; }
    fi
    command -v "$LLVM_PROFDATA" &>/dev/null || die "llvm-profdata not found"
    command -v "$LLVM_COV"      &>/dev/null || die "llvm-cov not found"
    command -v clang &>/dev/null || die "clang not found"
}

build_coverage_binary() {
    if [ -f "$COV_BIN" ]; then
        echo "  (cjson_cov_replay already exists, skipping build)"
        return
    fi
    echo "Building cjson_cov_replay (coverage instrumented)..."

    local main_src="$REPO/cov_replay_cjson_main.c"
    cat > "$main_src" << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

extern int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        if (!f) continue;
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        rewind(f);
        if (sz > 0) {
            uint8_t *buf = (uint8_t *)malloc(sz);
            if (buf) {
                fread(buf, 1, sz, f);
                LLVMFuzzerTestOneInput(buf, sz);
                free(buf);
            }
        }
        fclose(f);
    }
    return 0;
}
EOF

    clang -fprofile-instr-generate -fcoverage-mapping -O2 -g \
        -I"$CJSON_TARGET" \
        "$main_src" \
        "$CJSON_TARGET/cjson_harness.c" \
        "$CJSON_TARGET/cJSON.c" \
        -o "$COV_BIN" \
        -ldl
    echo "  -> built $COV_BIN"
}

parse_lf_stat() {
    local key="$1" logfile="$2"
    grep -oP "${key}:\s*\K[0-9]+" "$logfile" 2>/dev/null | tail -1 || echo "0"
}

measure_coverage() {
    local label="$1" corpus_dir="$2" profdata_out="$3"
    local profraw_dir="$OUTDIR/profraw_${label}"
    mkdir -p "$profraw_dir"

    local corpus_files=()
    while IFS= read -r -d '' f; do
        corpus_files+=("$f")
    done < <(find "$corpus_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    if [ "${#corpus_files[@]}" -eq 0 ]; then
        echo "  [coverage] No corpus files for $label" >&2
        return 1
    fi

    local i=0
    for f in "${corpus_files[@]}"; do
        LLVM_PROFILE_FILE="$profraw_dir/${i}.profraw" \
            "$COV_BIN" "$f" 2>/dev/null || true
        i=$((i + 1))
    done

    local profraw_files
    profraw_files=$(find "$profraw_dir" -name "*.profraw" 2>/dev/null | wc -l)
    if [ "$profraw_files" -eq 0 ]; then
        echo "  [coverage] No .profraw files generated for $label" >&2
        return 1
    fi

    "$LLVM_PROFDATA" merge -sparse "$profraw_dir"/*.profraw -o "$profdata_out" 2>/dev/null
}

get_branch_cov() {
    local profdata="$1"
    "$LLVM_COV" report "$COV_BIN" -instr-profile="$profdata" 2>/dev/null \
        | awk '/^TOTAL/ { print $NF }' || echo "N/A"
}

count_crashes() {
    local dir="$1"
    find "$dir" -maxdepth 1 -name "crash-*" -o -name "timeout-*" 2>/dev/null | wc -l || echo 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
check_bins
build_coverage_binary

mkdir -p "$OUTDIR/lf_corpus" "$OUTDIR/wf_corpus"

echo "============================================"
echo "  cJSON Fuzzer Benchmark  (${DURATION}s each)"

echo "  Run ID : $RUN_ID"
echo "  Output : $OUTDIR"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# 1. LibFuzzer
# ---------------------------------------------------------------------------
echo "[1/3] LibFuzzer — running for ${DURATION}s..."
LF_LOG="$OUTDIR/lf.log"

"$LF_BIN" \
    "$OUTDIR/lf_corpus" \
    "$SEEDS" \
    -max_total_time="$DURATION" \
    -print_final_stats=1 \
    2>&1 | tee "$LF_LOG" || true

LF_EXECS=$(parse_lf_stat "exec/s" "$LF_LOG")
LF_INLINE_COV=$(parse_lf_stat "cov" "$LF_LOG")
LF_CORPUS_SIZE=$(find "$OUTDIR/lf_corpus" -maxdepth 1 -type f | wc -l)
LF_CRASHES=$(count_crashes "$OUTDIR/lf_corpus")
echo "  -> exec/s: $LF_EXECS  |  inline cov edges: $LF_INLINE_COV  |  corpus: $LF_CORPUS_SIZE  |  crashes: $LF_CRASHES"
echo ""

# ---------------------------------------------------------------------------
# 2. WingFuzz
# ---------------------------------------------------------------------------
echo "[2/3] WingFuzz — running for ${DURATION}s..."
WF_LOG="$OUTDIR/wf.log"

LLVM_PROFILE_FILE="$OUTDIR/wf_live.profraw" \
    "$WF_BIN" \
    "$OUTDIR/wf_corpus" \
    "$SEEDS" \
    -max_total_time="$DURATION" \
    -print_final_stats=1 \
    2>&1 | tee "$WF_LOG" || true

WF_EXECS=$(parse_lf_stat "exec/s" "$WF_LOG")
WF_INLINE_COV=$(parse_lf_stat "cov" "$WF_LOG")
WF_CORPUS_SIZE=$(find "$OUTDIR/wf_corpus" -maxdepth 1 -type f | wc -l)
WF_CRASHES=$(count_crashes "$OUTDIR/wf_corpus")
echo "  -> exec/s: $WF_EXECS  |  inline cov edges: $WF_INLINE_COV  |  corpus: $WF_CORPUS_SIZE  |  crashes: $WF_CRASHES"
echo ""

# ---------------------------------------------------------------------------
# 3. DDFuzz (via Docker)
# ---------------------------------------------------------------------------
echo "[3/3] DDFuzz — running for ${DURATION}s (Docker)..."
DDF_LOG="$OUTDIR/ddf.log"
DDF_OUT_HOST="$OUTDIR/ddf"
DDF_OUT_DOCKER="/workspaces/CyberSecurity/results/benchmark_cjson_${RUN_ID}/ddf"
DDF_EXECS="N/A"; DDF_CORPUS_SIZE="N/A"; DDF_CRASHES="N/A"; DDF_BRANCH_COV="N/A"

if [ "$HAS_DDFUZZ" -eq 1 ]; then
    docker run --rm \
        -v "$REPO:/workspaces/CyberSecurity" \
        -e AFL_SKIP_CPUFREQ=1 \
        -e AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
        -e AFL_NO_UI=1 \
        --privileged \
        ddfuzz:local \
        bash -c "
            timeout $DURATION afl-fuzz \
                -i /workspaces/CyberSecurity/cjson_corpus \
                -o $DDF_OUT_DOCKER \
                -- $DDF_BIN || true
            chmod -R 755 $DDF_OUT_DOCKER
        " 2>&1 | tee "$DDF_LOG" || true

    DDF_STATS="$DDF_OUT_HOST/default/fuzzer_stats"
    DDF_QUEUE="$DDF_OUT_HOST/default/queue"
    DDF_CRASH_DIR="$DDF_OUT_HOST/default/crashes"

    if [ -f "$DDF_STATS" ]; then
        DDF_EXECS=$(awk -F' *: *' '/execs_per_sec/  { printf "%d", $2 }' "$DDF_STATS")
        DDF_CORPUS_SIZE=$(awk -F' *: *' '/corpus_count|paths_total/ { print $2; exit }' "$DDF_STATS")
        DDF_CRASHES=$(find "$DDF_CRASH_DIR" -maxdepth 1 -type f ! -name "README.txt" 2>/dev/null | wc -l || echo 0)
    fi
else
    echo "  (skipped)"
    touch "$DDF_LOG"
fi
echo "  -> exec/s: $DDF_EXECS  |  corpus: $DDF_CORPUS_SIZE  |  crashes: $DDF_CRASHES"
echo ""

# ---------------------------------------------------------------------------
# Coverage measurement
# ---------------------------------------------------------------------------
echo "Measuring branch coverage for each corpus..."

lf_cov_src="$OUTDIR/lf_corpus"; [ "$(find "$lf_cov_src" -maxdepth 1 -type f | wc -l)" -eq 0 ] && lf_cov_src="$SEEDS"
wf_cov_src="$OUTDIR/wf_corpus"; [ "$(find "$wf_cov_src" -maxdepth 1 -type f | wc -l)" -eq 0 ] && wf_cov_src="$SEEDS"

measure_coverage "lf"  "$lf_cov_src" "$OUTDIR/lf.profdata" && \
    LF_BRANCH_COV=$(get_branch_cov "$OUTDIR/lf.profdata")    || LF_BRANCH_COV="N/A"

measure_coverage "wf"  "$wf_cov_src" "$OUTDIR/wf.profdata" && \
    WF_BRANCH_COV=$(get_branch_cov "$OUTDIR/wf.profdata")    || WF_BRANCH_COV="N/A"

if [ "$HAS_DDFUZZ" -eq 1 ] && [ -d "${DDF_QUEUE:-}" ] && \
   [ "$(find "$DDF_QUEUE" -maxdepth 1 -type f | wc -l)" -gt 0 ]; then
    measure_coverage "ddf" "$DDF_QUEUE" "$OUTDIR/ddf.profdata" && \
        DDF_BRANCH_COV=$(get_branch_cov "$OUTDIR/ddf.profdata")  || DDF_BRANCH_COV="N/A"
fi


# ---------------------------------------------------------------------------
# Results table
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  RESULTS  (${DURATION}s per fuzzer)"
echo "============================================"
printf "%-12s  %10s  %10s  %10s  %12s  %12s\n" \
    "Fuzzer" "Exec/s" "Corpus" "Crashes" "Cov Edges" "Branch Cov%"
printf "%-12s  %10s  %10s  %10s  %12s  %12s\n" \
    "----------" "--------" "--------" "--------" "----------" "-----------"
printf "%-12s  %10s  %10s  %10s  %12s  %12s\n" \
    "LibFuzzer" "$LF_EXECS" "$LF_CORPUS_SIZE" "$LF_CRASHES" "$LF_INLINE_COV" "$LF_BRANCH_COV"
printf "%-12s  %10s  %10s  %10s  %12s  %12s\n" \
    "WingFuzz"  "$WF_EXECS" "$WF_CORPUS_SIZE" "$WF_CRASHES" "$WF_INLINE_COV" "$WF_BRANCH_COV"
printf "%-12s  %10s  %10s  %10s  %12s  %12s\n" \
    "DDFuzz"    "$DDF_EXECS" "$DDF_CORPUS_SIZE" "$DDF_CRASHES" "N/A" "$DDF_BRANCH_COV"
echo ""
echo "Cov Edges   = inline coverage edge counter reported by LibFuzzer/WingFuzz"
echo "Branch Cov% = LLVM branch coverage from replaying corpus (fair, same binary)"
echo ""

best_pct=0; winner="(unknown)"
for pair in "LibFuzzer:$LF_BRANCH_COV" "WingFuzz:$WF_BRANCH_COV" "DDFuzz:$DDF_BRANCH_COV"; do
    name="${pair%%:*}"; pct="${pair##*:}"
    num="${pct//%/}"
    if [[ "$num" =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
       awk "BEGIN { exit !($num > $best_pct) }"; then
        best_pct="$num"; winner="$name"
    fi
done
echo "Best branch coverage: $winner ($best_pct%)"
echo ""
echo "Full logs and corpora saved to: $OUTDIR"

mkdir -p "$REPO/results"
cat > "$REPO/results/latest_cjson.env" << ENVEOF
LF_BRANCH_COV=$LF_BRANCH_COV
LF_EXECS=$LF_EXECS
WF_BRANCH_COV=$WF_BRANCH_COV
WF_EXECS=$WF_EXECS
DDF_BRANCH_COV=$DDF_BRANCH_COV
DDF_EXECS=$DDF_EXECS
ENVEOF
