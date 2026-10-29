add_library(olcore STATIC
  src/ball_physics.cpp
  src/arc0.cpp
  src/binary_reader.cpp
  src/btcv.cpp
  src/bunky.cpp
  src/course.cpp
  src/crz.cpp
  src/carrera_store.cpp
  src/inflate.cpp
  src/ls_archive.cpp
  src/lzw.cpp
  src/model.cpp
  src/object_library.cpp
  src/scoring.cpp
  src/shot.cpp
  src/ssf.cpp
  src/strings.cpp
  src/swing.cpp
  src/wav.cpp
)
target_include_directories(olcore PUBLIC include)

add_executable(olcore_tests tests/test_main.cpp)
target_link_libraries(olcore_tests PRIVATE olcore)
add_test(NAME olcore_tests COMMAND olcore_tests)

add_executable(olcourse_tests tests/test_course.cpp)
target_link_libraries(olcourse_tests PRIVATE olcore)
add_test(NAME olcourse_tests COMMAND olcourse_tests)
