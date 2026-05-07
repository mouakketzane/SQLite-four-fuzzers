# Fuzzer Benchmark Results

Each fuzzer ran for **1s** per target. Branch coverage was measured by
replaying the final corpus through a shared LLVM-instrumented binary (fair
comparison — same binary for all three fuzzers on each target).

## SQLite

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 13.02% | 600 |
| DDFuzz    | 13.66% | 22543 |

## RHash

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 5.70% | 15 |
| DDFuzz    | 7.45% | 30186 |

## cJSON

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 25.52% | 1990 |
| DDFuzz    | 32.08% | 20959 |

## re2

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 70.00% | 831 |
| DDFuzz    | 70.00% | 15235 |

> Branch Cov = LLVM branch coverage % from `llvm-cov report` over the final corpus.
> Exec/s = executions per second reported at end of run.
> Fuzzing time = 1s per fuzzer per target.
> re2 coverage measured over harness only (system shared library).
> N/A = exec/s could not be determined for this fuzzer/target combination.

## Injected Bug Findings

Each cell shows **seconds from fuzzer start to first crash** for that bug, or `not_found`.

| Target | Bug     | Description                          | Difficulty        | LibFuzzer  | DDFuzz     |
|--------|---------|--------------------------------------|-------------------|:----------:|:----------:|
| cJSON  | BUG_C1  | Off-by-one in string alloc           | Easy (~2 min)     | 0 | not_found |
| cJSON  | BUG_C2  | Escape-count underflow on print      | Hard (~2 hr)      | not_found | not_found |
| RHash  | BUG_R1  | MD5 leftover copy overflow           | Easy (~5 min)     | 1 | not_found |
| RHash  | BUG_R2  | SHA1 stack overflow at len%64==55    | Hard (~1 hr)      | not_found | not_found |
| re2    | BUG_RE1 | AllocInst memmove OOB read           | Medium (~20 min)  | 0 | not_found |
| SQLite | BUG_S1  | Long-identifier stack overflow       | Medium (~20 min)  | not_found | not_found |
| SQLite | BUG_S2  | WINDOW/FILTER keyword stack overflow | Hard (~2 hr)      | not_found | not_found |

## Fuzzer Score (Bugs Found)

A bug counts as "found" if any crash triggering it was discovered during the run.
Total implanted bugs: **7**.  Best fuzzer: **LibFuzzer**.

| Fuzzer    | Bugs Found       | Score |
|-----------|:----------------:|------:|
| LibFuzzer | 3 / 7  | 43% |
| DDFuzz    | 0 / 7 | 0% |
