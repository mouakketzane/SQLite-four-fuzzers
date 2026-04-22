cmake_minimum_required(VERSION 3.10)
project(RE2Fuzz CXX)

add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
add_link_options(-fsanitize=address,undefined)

find_package(PkgConfig REQUIRED)
pkg_check_modules(RE2 REQUIRED re2)
