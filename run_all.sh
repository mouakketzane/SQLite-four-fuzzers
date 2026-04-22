#!/usr/bin/env bash
# Run all fuzzers (LibFuzzer, WingFuzz, DDFuzz) on all targets
# and write RESULTS.md.
# Usage: ./run_all.sh [duration_seconds]  (default: 60)

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SECONDS_ARG="${1:-60}"

echo "Running all benchmarks for ${SECONDS_ARG}s per fuzzer per target..."
echo ""

"$REPO/benchmark_sqlite.sh" "$SECONDS_ARG"
echo ""
"$REPO/benchmark_rhash.sh" "$SECONDS_ARG"
echo ""
"$REPO/benchmark_cjson.sh" "$SECONDS_ARG"
echo ""
"$REPO/benchmark_re2.sh" "$SECONDS_ARG"

# Load results written by each benchmark script
# shellcheck source=/dev/null
source "$REPO/results/latest_sqlite.env"
SQ_LF_COV=$LF_BRANCH_COV;  SQ_LF_EXECS=$LF_EXECS
SQ_WF_COV=$WF_BRANCH_COV;  SQ_WF_EXECS=$WF_EXECS
SQ_DDF_COV=$DDF_BRANCH_COV; SQ_DDF_EXECS=$DDF_EXECS
# shellcheck source=/dev/null
source "$REPO/results/latest_rhash.env"
RH_LF_COV=$LF_BRANCH_COV;  RH_LF_EXECS=$LF_EXECS
RH_WF_COV=$WF_BRANCH_COV;  RH_WF_EXECS=$WF_EXECS
RH_DDF_COV=$DDF_BRANCH_COV; RH_DDF_EXECS=$DDF_EXECS
# shellcheck source=/dev/null
source "$REPO/results/latest_cjson.env"
CJ_LF_COV=$LF_BRANCH_COV;  CJ_LF_EXECS=$LF_EXECS
CJ_WF_COV=$WF_BRANCH_COV;  CJ_WF_EXECS=$WF_EXECS
CJ_DDF_COV=$DDF_BRANCH_COV; CJ_DDF_EXECS=$DDF_EXECS
# shellcheck source=/dev/null
source "$REPO/results/latest_re2.env"
RE_LF_COV=$LF_BRANCH_COV;  RE_LF_EXECS=$LF_EXECS
RE_WF_COV=$WF_BRANCH_COV;  RE_WF_EXECS=$WF_EXECS
RE_DDF_COV=$DDF_BRANCH_COV; RE_DDF_EXECS=$DDF_EXECS

fmt_execs() { [[ "$1" =~ ^[0-9]+$ ]] && printf "%'.0f" "$1" || echo "$1"; }

cat > "$REPO/RESULTS.md" << EOF
# Fuzzer Benchmark Results

Each fuzzer ran for **${SECONDS_ARG}s** per target. Branch coverage was measured by
replaying the final corpus through a shared LLVM-instrumented binary (fair
comparison — same binary for all three fuzzers on each target).

## SQLite

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $SQ_LF_COV | $(fmt_execs "$SQ_LF_EXECS") |
| WingFuzz  | $SQ_WF_COV | $(fmt_execs "$SQ_WF_EXECS") |
| DDFuzz    | $SQ_DDF_COV | $(fmt_execs "$SQ_DDF_EXECS") |

## RHash

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $RH_LF_COV | $(fmt_execs "$RH_LF_EXECS") |
| WingFuzz  | $RH_WF_COV | $(fmt_execs "$RH_WF_EXECS") |
| DDFuzz    | $RH_DDF_COV | $(fmt_execs "$RH_DDF_EXECS") |

## cJSON

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $CJ_LF_COV | $(fmt_execs "$CJ_LF_EXECS") |
| WingFuzz  | $CJ_WF_COV | $(fmt_execs "$CJ_WF_EXECS") |
| DDFuzz    | $CJ_DDF_COV | $(fmt_execs "$CJ_DDF_EXECS") |

## re2

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | $RE_LF_COV | $(fmt_execs "$RE_LF_EXECS") |
| WingFuzz  | $RE_WF_COV | $(fmt_execs "$RE_WF_EXECS") |
| DDFuzz    | $RE_DDF_COV | $(fmt_execs "$RE_DDF_EXECS") |

> Branch Cov = LLVM branch coverage % from \`llvm-cov report\` over the final corpus.
> Exec/s = executions per second reported at end of run.
> Fuzzing time = ${SECONDS_ARG}s per fuzzer per target.
> re2 coverage measured over harness only (system shared library).
EOF

echo ""
echo "RESULTS.md updated."
echo "RESULTS.md: "
cat RESULTS.md
