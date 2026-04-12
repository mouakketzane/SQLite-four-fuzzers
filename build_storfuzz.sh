#!/bin/bash

# Navigate to the storfuzz build directory 

# Run your build commands
# export LIBAFL_EDGES_MAP_SIZE=262144
# export LIBAFL_EDGES_MAP_SIZE_MAX=262144
# export STORFUZZ_MAP_SIZE=262144
# export CFLAGS="-fsanitize-coverage=trace-pc-guard"
# export CXXFLAGS="-fsanitize-coverage=trace-pc-guard"

# cargo build --release





cd /workspaces/CyberSecurity/src/StorFuzz/LibAFL


STORFUZZ_MAP_SIZE=131072 \
LIBAFL_EDGES_MAP_SIZE_IN_USE=65536 \
CFLAGS="" CXXFLAGS="" \
cargo build --release -p libafl_cc


cd fuzzers/storfuzz_fuzzbench_in_process
STORFUZZ_MAP_SIZE=131072 \
LIBAFL_EDGES_MAP_SIZE_IN_USE=65536 \
CFLAGS="" CXXFLAGS="" \
cargo build --release

STORFUZZ_MAP_SIZE=131072 \
LIBAFL_EDGES_MAP_SIZE_IN_USE=65536 \
./target/release/libafl_cc --libafl \
    /workspaces/CyberSecurity/test_targets/sqlite/sqlite_harness.c \
    /workspaces/CyberSecurity/test_targets/sqlite/sqlite3.c \
    -o storfuzz_target -lpthread -ldl