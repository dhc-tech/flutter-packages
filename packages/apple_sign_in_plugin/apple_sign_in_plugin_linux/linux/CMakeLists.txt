cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "apple_sign_in_plugin_linux")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "apple_sign_in_plugin_linux_plugin")

add_library(${PLUGIN_NAME} SHARED
  "apple_sign_in_plugin_linux.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# List of absolute paths to libraries that should be bundled with the plugin
set(apple_sign_in_plugin_linux_bundled_libraries
  ""
  PARENT_SCOPE
)
