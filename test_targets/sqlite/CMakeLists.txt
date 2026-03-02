cmake_minimum_required(VERSION 3.10)
project(SQLiteFuzz C)

# Enable AddressSanitizer (Essential for catching memory bugs)
add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
add_link_options(-fsanitize=address,undefined)

# SQLite-specific hardening & performance flags
# OMIT_RANDOMNESS ensures the fuzzer gets the same result for the same input
add_definitions(
    -DSQLITE_OMIT_RANDOMNESS 
    -DSQLITE_THREADSAFE=0 
    -DSQLITE_ENABLE_DEBUG 
    -DSQLITE_ENABLE_MEMORY_MANAGEMENT
)

# Create the SQLite library
add_library(sqlite3_lib STATIC sqlite3.c)


