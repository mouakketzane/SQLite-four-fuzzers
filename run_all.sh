#!/usr/bin/env bash
# run_all.sh — Bootstrap a fresh machine, build all fuzzers, run all benchmarks,
# and write RESULTS.md.
#
# Usage: ./run_all.sh [duration_seconds]  (default: 60)
#
# On the first run this script will:
#   1. Install system packages (apt/Debian-Ubuntu only; manual install required elsewhere)
#   2. Build the ddfuzz:local Docker image
#   3. Clone RHash and create its fuzzing harness (test_targets/RHash)
#   4. Create minimal seed corpora for all four targets
#   5. Build all fuzzer binaries (LibFuzzer, WingFuzz, DDFuzz × 4 targets)
#   6. Run benchmark_*.sh scripts and write RESULTS.md
#
# WingFuzz runtime libraries are pre-built in prebuilt/wingfuzz/ — no LLVM 13 needed.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SECONDS_ARG="${1:-60}"

###############################################################################
# HELPERS
###############################################################################
info()  { echo "[setup] $*"; }
build() { echo "[build] $*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }

###############################################################################
# 1. SYSTEM DEPENDENCIES  (Debian / Ubuntu)
###############################################################################
install_system_deps() {
    if ! command -v apt-get &>/dev/null; then
        info "Non-Debian system — ensure these are installed manually:"
        info "  clang clang++ cmake make git pkg-config libre2-dev docker build-essential"
        return
    fi

    info "Checking system packages..."
    local pkgs=()

    command -v clang        &>/dev/null || pkgs+=(clang)
    command -v cmake        &>/dev/null || pkgs+=(cmake)
    command -v make         &>/dev/null || pkgs+=(make)
    command -v git          &>/dev/null || pkgs+=(git)
    command -v pkg-config   &>/dev/null || pkgs+=(pkg-config)
    command -v wget         &>/dev/null || pkgs+=(wget)
    command -v docker       &>/dev/null || pkgs+=(docker.io)
    pkg-config --exists re2 2>/dev/null || pkgs+=(libre2-dev)
    dpkg -s build-essential &>/dev/null 2>&1 || pkgs+=(build-essential)

    if [ ${#pkgs[@]} -gt 0 ]; then
        info "Installing: ${pkgs[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y "${pkgs[@]}"
    fi

    info "System packages OK."
}

###############################################################################
# 2. ENSURE UNVERSIONED llvm-profdata / llvm-cov ARE ON PATH
###############################################################################
setup_llvm_tools() {
    local link_dir
    if [ -w /usr/local/bin ]; then
        link_dir=/usr/local/bin
    else
        link_dir="$HOME/.local/bin"
        mkdir -p "$link_dir"
        # Make sure ~/.local/bin is on PATH for this session
        export PATH="$link_dir:$PATH"
    fi

    for tool in llvm-profdata llvm-cov; do
        if command -v "$tool" &>/dev/null; then
            continue
        fi
        local found=""
        for ver in -19 -18 -17 -16 -15 -14 -13 -12 -11; do
            if command -v "${tool}${ver}" &>/dev/null; then
                found="${tool}${ver}"
                break
            fi
        done
        if [ -n "$found" ]; then
            info "Linking $link_dir/$tool -> $found"
            ln -sf "$(command -v "$found")" "$link_dir/$tool"
        else
            die "$tool not found — install an llvm package (e.g. llvm-18)"
        fi
    done
}

###############################################################################
# 3. CHECK PRE-BUILT WINGFUZZ LIBRARIES
###############################################################################
# check_wingfuzz_libs() {
#     local libmain="$REPO/prebuilt/wingfuzz/libwingfuzz_main.a"
#     local libstatic="$REPO/prebuilt/wingfuzz/libwingfuzz_static.a"
#     [ -f "$libmain"   ] || die "prebuilt/wingfuzz/libwingfuzz_main.a missing — check your git clone"
#     [ -f "$libstatic" ] || die "prebuilt/wingfuzz/libwingfuzz_static.a missing — check your git clone"
#     info "WingFuzz pre-built libraries present."
# }

###############################################################################
# 4. BUILD DDFuzz DOCKER IMAGE
###############################################################################
build_ddfuzz_image() {
    if docker image inspect ddfuzz:local &>/dev/null 2>&1; then
        info "ddfuzz:local Docker image already present."
        return
    fi
    info "Building ddfuzz:local Docker image (this may take several minutes)..."
    docker build \
        -f "$REPO/.devcontainer/DDFuzz/Dockerfile.DDFuzz" \
        -t ddfuzz:local \
        "$REPO"
    info "ddfuzz:local built."
}

###############################################################################
# 5. SEED CORPORA
###############################################################################
create_seed_corpora() {
    mkdir -p "$REPO/sqlite_corpus"
    if [ -z "$(ls -A "$REPO/sqlite_corpus" 2>/dev/null)" ]; then
        printf 'SELECT 1;' \
            > "$REPO/sqlite_corpus/seed1"
        printf 'CREATE TABLE t(x);INSERT INTO t VALUES(1);SELECT * FROM t;' \
            > "$REPO/sqlite_corpus/seed2"
        info "Created sqlite_corpus seeds."
    fi

    mkdir -p "$REPO/rhash_corpus"
    if [ -z "$(ls -A "$REPO/rhash_corpus" 2>/dev/null)" ]; then
        printf 'hello world' > "$REPO/rhash_corpus/seed1"
        printf '\x00\x01\x02\x03\x04\x05\x06\x07' > "$REPO/rhash_corpus/seed2"
        info "Created rhash_corpus seeds."
    fi

    mkdir -p "$REPO/cjson_corpus"
    if [ -z "$(ls -A "$REPO/cjson_corpus" 2>/dev/null)" ]; then
        printf '{"key":"value","num":42}' > "$REPO/cjson_corpus/seed1"
        printf '[1,2,3,true,false,null]'  > "$REPO/cjson_corpus/seed2"
        info "Created cjson_corpus seeds."
    fi

    mkdir -p "$REPO/re2_corpus"
    if [ -z "$(ls -A "$REPO/re2_corpus" 2>/dev/null)" ]; then
        printf 'hello'       > "$REPO/re2_corpus/seed1"
        printf '[a-z]+'      > "$REPO/re2_corpus/seed2"
        printf '(\d+\.\d+)'  > "$REPO/re2_corpus/seed3"
        info "Created re2_corpus seeds."
    fi
}

###############################################################################
# 6. SET UP RHash TARGET
###############################################################################
setup_rhash_target() {
    local rhash_dir="$REPO/test_targets/RHash"

    if [ ! -f "$rhash_dir/librhash/rhash.h" ]; then
        info "Cloning RHash source into test_targets/RHash..."
        rm -rf "$rhash_dir"
        git clone --depth=1 https://github.com/rhash/RHash.git "$rhash_dir"
        info "RHash cloned."
    fi

    if [ ! -f "$rhash_dir/rhash_harness.c" ]; then
        info "Creating rhash_harness.c..."
        cat > "$rhash_dir/rhash_harness.c" << 'HARNESS_EOF'
#include <stdint.h>
#include <stdlib.h>
#include "librhash/rhash.h"

#ifdef __cplusplus
extern "C" {
#endif

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    static int inited = 0;
    if (!inited) { rhash_library_init(); inited = 1; }

    unsigned char digest[64];
    rhash_msg(RHASH_MD5,    data, size, digest);
    rhash_msg(RHASH_SHA1,   data, size, digest);
    rhash_msg(RHASH_SHA256, data, size, digest);
    rhash_msg(RHASH_CRC32,  data, size, digest);
    return 0;
}

#ifdef __cplusplus
}
#endif
HARNESS_EOF
        info "Created rhash_harness.c."
    fi
}

###############################################################################
# 7. BUILD ALL FUZZER BINARIES
###############################################################################
build_all_fuzzers() {

    # ── SQLite ────────────────────────────────────────────────────────────────
    if [ ! -f "$REPO/sqlite_libfuzzer" ] || [ ! -f "$REPO/sqlite3_DDFuzzer" ]; then  # || [ ! -f "$REPO/sqlite_wingfuzzer_real" ]
        build "Building SQLite fuzzer binaries..."
        "$REPO/build_sqlite.sh"
    else
        build "SQLite binaries already present (libfuzzer + wingfuzzer + DDFuzzer)."
    fi

    # ── cJSON ─────────────────────────────────────────────────────────────────
    if [ ! -f "$REPO/cjson_libfuzzer" ] || [ ! -f "$REPO/cjson_DDFuzzer" ]; then  # || [ ! -f "$REPO/cjson_wingfuzz_real" ]
        build "Building cJSON fuzzer binaries..."
        "$REPO/build_cjson.sh"
    else
        build "cJSON binaries already present (libfuzzer + wingfuzz + DDFuzzer)."
    fi

    # ── re2 ───────────────────────────────────────────────────────────────────
    if [ ! -f "$REPO/re2_libfuzzer" ] || [ ! -f "$REPO/re2_DDFuzzer" ]; then  # || [ ! -f "$REPO/re2_wingfuzz_real" ]
        build "Building re2 fuzzer binaries..."
        "$REPO/build_re2.sh"
    else
        build "re2 binaries already present (libfuzzer + wingfuzz + DDFuzzer)."
    fi

    # ── RHash ─────────────────────────────────────────────────────────────────
    if [ ! -f "$REPO/rhash_libfuzzer" ] || [ ! -f "$REPO/rhash_DDFuzzer" ]; then  # || [ ! -f "$REPO/rhash_wingfuzz_real" ]
        build "Building RHash fuzzer binaries..."
        "$REPO/build_rhash.sh"
    else
        build "RHash binaries already present (libfuzzer + wingfuzz + DDFuzzer)."
    fi

    build "All fuzzer binaries ready."
}

###############################################################################
# BOOTSTRAP SEQUENCE
###############################################################################
echo "============================================================"
echo "  run_all.sh  — bootstrapping and running all benchmarks"
echo "  Duration   : ${SECONDS_ARG}s per fuzzer per target"
echo "============================================================"
echo ""

install_system_deps
setup_llvm_tools
# check_wingfuzz_libs
build_ddfuzz_image
create_seed_corpora
setup_rhash_target
build_all_fuzzers

echo ""
echo "============================================================"
echo "  All prerequisites satisfied — running benchmarks"
echo "============================================================"
echo ""

###############################################################################
# RUN BENCHMARKS
###############################################################################
"$REPO/benchmark_sqlite.sh" "$SECONDS_ARG"
echo ""
"$REPO/benchmark_rhash.sh" "$SECONDS_ARG"
echo ""
"$REPO/benchmark_cjson.sh" "$SECONDS_ARG"
echo ""
"$REPO/benchmark_re2.sh" "$SECONDS_ARG"

###############################################################################
# AGGREGATE RESULTS → RESULTS.md
###############################################################################

# shellcheck source=/dev/null
source "$REPO/results/latest_sqlite.env"
SQ_LF_COV=$LF_BRANCH_COV;  SQ_LF_EXECS=$LF_EXECS
# SQ_WF_COV=$WF_BRANCH_COV;  SQ_WF_EXECS=$WF_EXECS
SQ_DDF_COV=$DDF_BRANCH_COV; SQ_DDF_EXECS=$DDF_EXECS
SQ_LF_BUGS=${LF_BUGS:-none}; SQ_DDF_BUGS=${DDF_BUGS:-none}
# SQ_WF_BUGS=${WF_BUGS:-none}
# shellcheck source=/dev/null
source "$REPO/results/latest_rhash.env"
RH_LF_COV=$LF_BRANCH_COV;  RH_LF_EXECS=$LF_EXECS
# RH_WF_COV=$WF_BRANCH_COV;  RH_WF_EXECS=$WF_EXECS
RH_DDF_COV=$DDF_BRANCH_COV; RH_DDF_EXECS=$DDF_EXECS
RH_LF_BUGS=${LF_BUGS:-none}; RH_DDF_BUGS=${DDF_BUGS:-none}
# RH_WF_BUGS=${WF_BUGS:-none}
# shellcheck source=/dev/null
source "$REPO/results/latest_cjson.env"
CJ_LF_COV=$LF_BRANCH_COV;  CJ_LF_EXECS=$LF_EXECS
# CJ_WF_COV=$WF_BRANCH_COV;  CJ_WF_EXECS=$WF_EXECS
CJ_DDF_COV=$DDF_BRANCH_COV; CJ_DDF_EXECS=$DDF_EXECS
CJ_LF_BUGS=${LF_BUGS:-none}; CJ_DDF_BUGS=${DDF_BUGS:-none}
# CJ_WF_BUGS=${WF_BUGS:-none}
# shellcheck source=/dev/null
source "$REPO/results/latest_re2.env"
RE_LF_COV=$LF_BRANCH_COV;  RE_LF_EXECS=$LF_EXECS
# RE_WF_COV=$WF_BRANCH_COV;  RE_WF_EXECS=$WF_EXECS
RE_DDF_COV=$DDF_BRANCH_COV; RE_DDF_EXECS=$DDF_EXECS
RE_LF_BUGS=${LF_BUGS:-none}; RE_DDF_BUGS=${DDF_BUGS:-none}
# RE_WF_BUGS=${WF_BUGS:-none}

fmt_execs() { [[ "$1" =~ ^[0-9]+$ ]] && printf "%'.0f" "$1" || echo "$1"; }

# Extract the timing for a single bug ID from a comma-separated bug string.
# e.g. extract_bug_time BUG_C1 "BUG_C1:42,BUG_C2:not_found"  =>  "42"
extract_bug_time() {
    local bug_id="$1" bug_string="$2"
    local val
    val=$(echo "$bug_string" | grep -oP "${bug_id}:\K[^,]+" 2>/dev/null || true)
    echo "${val:-not_found}"
}

# Return 0 (true) if a bug timing value means the bug was found.
is_found() { [ "$1" != "not_found" ] && [ "$1" != "none" ] && [ -n "$1" ]; }

# Count how many of the supplied timing values represent a found bug.
count_found() {
    local count=0
    for val in "$@"; do
        if is_found "$val"; then count=$((count + 1)); fi
    done
    echo "$count"
}

# Per-bug per-fuzzer timing values (seconds elapsed, or "not_found")
C1_LF=$(extract_bug_time  "BUG_C1"  "$CJ_LF_BUGS");  C1_DDF=$(extract_bug_time  "BUG_C1"  "$CJ_DDF_BUGS")  # C1_WF=$(extract_bug_time  "BUG_C1"  "$CJ_WF_BUGS")
C2_LF=$(extract_bug_time  "BUG_C2"  "$CJ_LF_BUGS");  C2_DDF=$(extract_bug_time  "BUG_C2"  "$CJ_DDF_BUGS")  # C2_WF=$(extract_bug_time  "BUG_C2"  "$CJ_WF_BUGS")
R1_LF=$(extract_bug_time  "BUG_R1"  "$RH_LF_BUGS");  R1_DDF=$(extract_bug_time  "BUG_R1"  "$RH_DDF_BUGS")  # R1_WF=$(extract_bug_time  "BUG_R1"  "$RH_WF_BUGS")
R2_LF=$(extract_bug_time  "BUG_R2"  "$RH_LF_BUGS");  R2_DDF=$(extract_bug_time  "BUG_R2"  "$RH_DDF_BUGS")  # R2_WF=$(extract_bug_time  "BUG_R2"  "$RH_WF_BUGS")
RE1_LF=$(extract_bug_time "BUG_RE1" "$RE_LF_BUGS");  RE1_DDF=$(extract_bug_time "BUG_RE1" "$RE_DDF_BUGS")  # RE1_WF=$(extract_bug_time "BUG_RE1" "$RE_WF_BUGS")
S1_LF=$(extract_bug_time  "BUG_S1"  "$SQ_LF_BUGS");  S1_DDF=$(extract_bug_time  "BUG_S1"  "$SQ_DDF_BUGS")  # S1_WF=$(extract_bug_time  "BUG_S1"  "$SQ_WF_BUGS")
S2_LF=$(extract_bug_time  "BUG_S2"  "$SQ_LF_BUGS");  S2_DDF=$(extract_bug_time  "BUG_S2"  "$SQ_DDF_BUGS")  # S2_WF=$(extract_bug_time  "BUG_S2"  "$SQ_WF_BUGS")

# Per-fuzzer scores: count of distinct bugs found
LF_SCORE=$(count_found  "$C1_LF"  "$C2_LF"  "$R1_LF"  "$R2_LF"  "$RE1_LF"  "$S1_LF"  "$S2_LF")
# WF_SCORE=$(count_found  "$C1_WF"  "$C2_WF"  "$R1_WF"  "$R2_WF"  "$RE1_WF"  "$S1_WF"  "$S2_WF")
DDF_SCORE=$(count_found "$C1_DDF" "$C2_DDF" "$R1_DDF" "$R2_DDF" "$RE1_DDF" "$S1_DDF" "$S2_DDF")
TOTAL_BUGS=7

# Determine the best-scoring fuzzer (highest bug count)
if [ "$LF_SCORE" -ge "$DDF_SCORE" ]; then
    BEST_FUZZER="LibFuzzer"
# elif [ "$WF_SCORE" -ge "$DDF_SCORE" ]; then
#     BEST_FUZZER="WingFuzz"
else
    BEST_FUZZER="DDFuzz"
fi

cat > "$REPO/RESULTS.md" << EOF
# Fuzzer Benchmark Results

Each fuzzer ran for **${SECONDS_ARG}s** per target. Branch coverage was measured by
replaying the final corpus through a shared LLVM-instrumented binary (fair
comparison — same binary for all three fuzzers on each target).

## SQLite

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $SQ_LF_COV | $(fmt_execs "$SQ_LF_EXECS") |
| DDFuzz    | $SQ_DDF_COV | $(fmt_execs "$SQ_DDF_EXECS") |

## RHash

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $RH_LF_COV | $(fmt_execs "$RH_LF_EXECS") |
| DDFuzz    | $RH_DDF_COV | $(fmt_execs "$RH_DDF_EXECS") |

## cJSON

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $CJ_LF_COV | $(fmt_execs "$CJ_LF_EXECS") |
| DDFuzz    | $CJ_DDF_COV | $(fmt_execs "$CJ_DDF_EXECS") |

## re2

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $RE_LF_COV | $(fmt_execs "$RE_LF_EXECS") |
| DDFuzz    | $RE_DDF_COV | $(fmt_execs "$RE_DDF_EXECS") |

> Branch Cov = LLVM branch coverage % from \`llvm-cov report\` over the final corpus.
> Exec/s = executions per second reported at end of run.
> Fuzzing time = ${SECONDS_ARG}s per fuzzer per target.
> re2 coverage measured over harness only (system shared library).
> N/A = exec/s could not be determined for this fuzzer/target combination.

## Injected Bug Findings

Each cell shows **seconds from fuzzer start to first crash** for that bug, or \`not_found\`.

| Target | Bug     | Description                          | Difficulty        | LibFuzzer  | DDFuzz     |
|--------|---------|--------------------------------------|-------------------|:----------:|:----------:|
| cJSON  | BUG_C1  | Off-by-one in string alloc           | Easy (~2 min)     | $C1_LF | $C1_DDF |
| cJSON  | BUG_C2  | Escape-count underflow on print      | Hard (~2 hr)      | $C2_LF | $C2_DDF |
| RHash  | BUG_R1  | MD5 leftover copy overflow           | Easy (~5 min)     | $R1_LF | $R1_DDF |
| RHash  | BUG_R2  | SHA1 stack overflow at len%64==55    | Hard (~1 hr)      | $R2_LF | $R2_DDF |
| re2    | BUG_RE1 | AllocInst memmove OOB read           | Medium (~20 min)  | $RE1_LF | $RE1_DDF |
| SQLite | BUG_S1  | Long-identifier stack overflow       | Medium (~20 min)  | $S1_LF | $S1_DDF |
| SQLite | BUG_S2  | WINDOW/FILTER keyword stack overflow | Hard (~2 hr)      | $S2_LF | $S2_DDF |

## Fuzzer Score (Bugs Found)

A bug counts as "found" if any crash triggering it was discovered during the run.
Total implanted bugs: **$TOTAL_BUGS**.  Best fuzzer: **$BEST_FUZZER**.

| Fuzzer    | Bugs Found       | Score |
|-----------|:----------------:|------:|
| LibFuzzer | $LF_SCORE / $TOTAL_BUGS  | $(awk "BEGIN { printf \"%.0f%%\", $LF_SCORE / $TOTAL_BUGS * 100 }") |
| DDFuzz    | $DDF_SCORE / $TOTAL_BUGS | $(awk "BEGIN { printf \"%.0f%%\", $DDF_SCORE / $TOTAL_BUGS * 100 }") |
EOF

echo ""
echo "RESULTS.md updated."
echo ""
cat "$REPO/RESULTS.md"
