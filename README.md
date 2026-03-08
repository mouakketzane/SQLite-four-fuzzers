## What is this Repo

This repo compares Data Coverage fuzzers available

## Setup

Run this command to pull the submodules like sqlite
```bash
git submodule update --init --recursive
```

## How to build 

First make the build directory
```bash
mkdir build && cd build
```

```bash
cmake ..
```

```bash
make
```

This will build wingfuzz all inside the build folder.

To build sqlite, run this in your terminal:

```bash
clang-13 -fprofile-instr-generate -fcoverage-mapping -O2 -g -fsanitize=fuzzer-no-link     -I/workspaces/CyberSecurity/test_targets/sqlite/     -c /workspaces/CyberSecurity/test_targets/sqlite/sqlite3.c     -o /workspaces/CyberSecurity/build/sqlite3.o
```

to build the harness: 

```bash
clang++-13 -O2 -g -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping    -I/workspaces/CyberSecurity/test_targets/sqlite/     -c /workspaces/CyberSecurity/test_targets/sqlite/sqlite_harness.cpp     -o /workspaces/CyberSecurity/build/harness.o

```


Link to the final fuzzer

```bash
clang++-13 -O2 -g -fsanitize=fuzzer     /workspaces/CyberSecurity/build/harness.o     /workspaces/CyberSecurity/build/sqlite3.o     -L/workspaces/CyberSecurity/build/src/wingfuzz     -lwingfuzz_main -lwingfuzz_static     -lpthread -ldl -o sqlite_wingfuzzer

```

To run wingfuzzer
```bash
LLVM_PROFILE_FILE="coverage.profraw" ./sqlite_wingfuzzer corpus/ -max_total_time=4
```
