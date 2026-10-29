add_library(olcore STATIC
  src/ball_physics.cpp
  src/binary_reader.cpp
  src/carrera_store.cpp
  src/golfer_anim.cpp
  src/ls_archive.cpp
  src/lzw.cpp
  src/scoring.cpp
  src/shot.cpp
  src/ssf.cpp
  src/swing.cpp
  src/wav.cpp
)
target_include_directories(olcore PUBLIC include)

add_executable(olcore_tests tests/test_main.cpp)
target_link_libraries(olcore_tests PRIVATE olcore)
add_test(NAME olcore_tests COMMAND olcore_tests)
