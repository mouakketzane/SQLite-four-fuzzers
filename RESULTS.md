# Fuzzer Benchmark Results

Each fuzzer ran for **1s** per target. Branch coverage was measured by
replaying the final corpus through a shared LLVM-instrumented binary (fair
comparison — same binary for all three fuzzers on each target).

## SQLite

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 13.73% | 11818 |
| WingFuzz  | 13.54% | 7591 |
| DDFuzz    | 13.62% | 25693 |

## RHash

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 6.96% | 146388 |
| WingFuzz  | 6.96% | 169445 |
| DDFuzz    | 6.96% | 47995 |

## cJSON

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 38.46% | 149516 |
| WingFuzz  | 37.24% | 237470 |
| DDFuzz    | 34.99% | 50509 |

## re2

| Fuzzer    | Branch Cov | Exec/s |
|-----------|----------:|-------:|
| LibFuzzer | 70.00% | 69115 |
| WingFuzz  | 70.00% | 41373 |
| DDFuzz    | 70.00% | 18580 |

> Branch Cov = LLVM branch coverage % from `llvm-cov report` over the final corpus.
> Exec/s = executions per second reported at end of run.
> Fuzzing time = 1s per fuzzer per target.
> re2 coverage measured over harness only (system shared library).
