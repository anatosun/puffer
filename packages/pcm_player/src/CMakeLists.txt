# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(pcm_player_library VERSION 0.0.1 LANGUAGES C)

add_library(pcm_player SHARED
  "pcm_player.c"
)

set_target_properties(pcm_player PROPERTIES
  PUBLIC_HEADER pcm_player.h
  OUTPUT_NAME "pcm_player"
)

target_compile_definitions(pcm_player PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(pcm_player PRIVATE "-Wl,-z,max-page-size=16384")
  # miniaudio loads AAudio or OpenSL ES at run time.
  target_link_libraries(pcm_player PRIVATE log)
elseif (UNIX)
  # miniaudio loads PulseAudio or ALSA at run time.
  find_package(Threads REQUIRED)
  target_link_libraries(pcm_player PRIVATE Threads::Threads ${CMAKE_DL_LIBS} m)
endif()
