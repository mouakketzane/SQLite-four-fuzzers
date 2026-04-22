## What is this Repo

This repo compares Data Coverage fuzzers available

## Requirements

- vscode 
- DevContainer VSCode extension
- Docker


## Setup

Run this command to pull the submodules like sqlite
If you see any error like No url found for submodule path, then you will need to cd into each fuzzer folder and run this command:
```bash
git submodule update --init --recursive
```

## How to build 

Reopen as a devcontainer: 
    1) Press Shift + Ctrl + P
    2) Click on `Dev Container: Rebuild and Reopen in Container`

Now that you have the devcontainer build: 

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
clang++-13 -O2 -g -fsanitize=address \
    -fprofile-instr-generate -fcoverage-mapping \
    /workspaces/CyberSecurity/build/harness.o \
    /workspaces/CyberSecurity/build/sqlite3.o \
    -Xlinker --start-group \
    /workspaces/CyberSecurity/build/src/wingfuzz/libwingfuzz_main.a \
    /workspaces/CyberSecurity/build/src/wingfuzz/libwingfuzz_static.a \
    -Xlinker --end-group \
    -lpthread -ldl -o sqlite_wingfuzzer_real
```

To run wingfuzzer
```bash
LLVM_PROFILE_FILE="coverage.profraw" ./sqlite_wingfuzzer_real sqlilte_corpus/ -max_total_time=4
```


# For wingfuzz for RHash
```bash
cd /workspaces/CyberSecurity/test_targets/RHash/librhash
```
# Clear out the standard libFuzzer objects we just made
```bash
rm -f *.o librhash.a
```

# Build the static library using the Wingfuzz wrapper
```bash
make CC="clang-13 -O2 -g -fsanitize=fuzzer-no-link -fprofile-instr-generate -fcoverage-mapping" lib-static
```

```bash
cd /workspaces/CyberSecurity
```

```bash
 clang++-13 -O2 -g -fsanitize=fuzzer,address     -fprofile-instr-generate -fcoverage-mapping     /workspaces/CyberSecurity/build/src/wingfuzz/libwingfuzz_main.a     /workspaces/CyberSecurity/build/src/wingfuzz/libwingfuzz_static.a     /workspaces/CyberSecurity/build/rhash_harness.o     /workspaces/CyberSecurity/test_targets/RHash/librhash/librhash.a     -o rhash_wingfuzz_real
```



# For libfuzzer

```bash
clang -g -O2 -fsanitize=fuzzer-no-link,address -c test_targets/sqlite/sqlite3.c -o sqlite3.o
```

link to sqlite harness

```bash
clang++ -g -O2 -fsanitize=fuzzer,address test_targets/sqlite/sqlite_harness.c sqlite3.o -o sqlite_libfuzzer -ldl -lpthread
```

# For building RHash: 

```bash
cd /workspaces/CyberSecurity/test_targets/RHash/librhash
```

Manually clean just this folder to force a recompile
```bash
rm -f *.o librhash.a
```

Compile the static library with your custom flags

```bash
make CC="clang -fsanitize=fuzzer-no-link,address -g" CFLAGS="-O2" lib-static
```

```bash
cd /workspaces/CyberSecurity
```
link to RHash harness

```bash
clang++ -g -O2 -fsanitize=fuzzer,address     test_targets/RHash/rhash_harness.c     test_targets/RHash/librhash/librhash.a     -o rhash_libfuzzer
```

Note WingFuzz is forked from libfuzzer so they are very similar
To check if right:

run the binary with the -help=1 flag and if it is wingfuzz check for any flags for data coverage.










## DDFuzz - DDFuzz does not work for sqlite amalgamation b/c data dependency graph takes too much memory - better to use the source code

Run these commands to activate DDFuzz in the env variable and allow DDfuzz to instrument sqlite
```bash
export DDG_INSTR=1
export AFL_LLVM_INSTRUMENT=classic

cd /workspaces/CyberSecurity/test_targets/sqlite3_full

CC=afl-clang-fast ./configure --enable-static --disable-shared --disable-amalgamation

make
```

Link Harness against the sqlite library
```bash
 afl-clang-fast -O2 -I. -fsanitize=fuzzer /workspaces/CyberSecurity/test_targets/sqlite/sqlite_harness.c /workspaces/CyberSecurity/test_targets/sqlite3_full/libsqlite3.a -o sqlite3_DDFuzzer -ldl -lpthread -lm

```

run
```
afl-fuzz -i inputs/ -o outputs/ -x /AFLplusplus/dictionaries/sql.dict -- ./sqlite3_DDFuzzer
```


afl-fuzz -i inputs/ -o outputs/ -x dictionaries/sql.dict -- ./sqlite3_fuzzer @@





# DDFuzz for Rhash


```bash
cd /workspaces/CyberSecurity/test_targets/RHash

export DDG_INSTR=1
export AFL_LLVM_INSTRUMENT=classic

CC=afl-clang-fast ./configure --enable-static

make 

afl-clang-fast -O2 -I. -I./librhash -fsanitize=fuzzer rhash_harness.c ./librhash/librhash.a -o rhash_DDFuzzer -ldl

afl-fuzz -i rhash_corpus/ -o outputs/ -- ./rhash_DDFuzzer

```


