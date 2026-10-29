add_library(olcore STATIC
  src/ball_physics.cpp
  src/binary_reader.cpp
)
target_include_directories(olcore PUBLIC include)

add_executable(olcore_tests tests/test_main.cpp)
target_link_libraries(olcore_tests PRIVATE olcore)
add_test(NAME olcore_tests COMMAND olcore_tests)
