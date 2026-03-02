cmake_minimum_required(VERSION 3.10)
project(DataCoverageFuzzerProject C CXX)

include(CheckCXXSourceCompiles)

add_subdirectory(test_targets)
add_subdirectory(src)

## TODO LATER 
#add_executable(data_fuzzer test_targets)

#target_link_libraries(data_fuzzer wingfuzz_static pthread dl)