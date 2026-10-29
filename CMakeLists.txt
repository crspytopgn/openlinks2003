cmake_minimum_required(VERSION 3.20)
project(OpenLinks2003 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  add_compile_options(/W4 /permissive-)
else()
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

enable_testing()

add_subdirectory(libs/olcore)
add_subdirectory(tools/oldump)
