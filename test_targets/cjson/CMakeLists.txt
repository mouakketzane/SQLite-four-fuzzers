cmake_minimum_required(VERSION 3.10)
project(cJSONFuzz C)

add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
add_link_options(-fsanitize=address,undefined)

add_library(cjson_lib STATIC cJSON.c)
