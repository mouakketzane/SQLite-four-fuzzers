# Fuzzer Benchmark Results

Each fuzzer ran for **60s** per target. Branch coverage was measured by
replaying the final corpus through a shared LLVM-instrumented binary (fair
comparison — same binary for all three fuzzers on each target).

## SQLite

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 3.98% | 16,069 |
| WingFuzz  | 3.99% | 19,414 |
| DDFuzz    | 4.09% | 13,875 |

## RHash

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 4.45% | 97,350 |
| WingFuzz  | 4.45% | 97,359 |
| DDFuzz    | 4.45% | 21,132 |

## cJSON

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 38.07% | 34,170 |
| WingFuzz  | 39.27% | 77,442 |
| DDFuzz    | 37.89% | 25,863 |

## re2

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 70.00% | 41,837 |
| WingFuzz  | 70.00% | 41,401 |
| DDFuzz    | 70.00% | 7,661 |

> Branch Cov = LLVM branch coverage % from `llvm-cov report` over the final corpus.
> Exec/s = executions per second reported at end of run.
> Fuzzing time = 60s per fuzzer per target.
> re2 coverage measured over harness only (system shared library).
