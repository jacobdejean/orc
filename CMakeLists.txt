cmake_minimum_required(VERSION 3.21)
project(cef_experiment CXX OBJCXX)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CEF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/cef")
if(NOT EXISTS "${CEF_ROOT}/include/cef_app.h")
  message(FATAL_ERROR
    "CEF not found in third_party/cef. Run scripts/fetch_cef.sh first.")
endif()

set(CEF_FRAMEWORK_DIR "${CEF_ROOT}/${CMAKE_BUILD_TYPE}")
set(CEF_FRAMEWORK "${CEF_FRAMEWORK_DIR}/Chromium Embedded Framework.framework")

# ---------------------------------------------------------------------------
# libcef_dll_wrapper: static helper library shipped as source with CEF.
# ---------------------------------------------------------------------------
file(GLOB_RECURSE CEF_WRAPPER_SOURCES
  "${CEF_ROOT}/libcef_dll/*.cc"
  "${CEF_ROOT}/libcef_dll/*.mm"
)
add_library(cef_dll_wrapper STATIC ${CEF_WRAPPER_SOURCES})
target_include_directories(cef_dll_wrapper PUBLIC "${CEF_ROOT}")
target_compile_definitions(cef_dll_wrapper PUBLIC
  WRAPPING_CEF_SHARED
  NDEBUG  # even in Debug builds the wrapper must match the binary's config
)
# Suppress noisy deprecation warnings from the wrapper.
target_compile_options(cef_dll_wrapper PRIVATE -w)

# ---------------------------------------------------------------------------
# Helper (subprocess) app bundles.
# ---------------------------------------------------------------------------
set(HELPER_VARIANTS "" "GPU" "Renderer" "Plugin")
set(APP_NAME "Experiment")
set(HELPER_TARGETS "")

foreach(variant IN LISTS HELPER_VARIANTS)
  if(variant STREQUAL "")
    set(helper_target "helper_base")
    set(helper_name "${APP_NAME} Helper")
    set(helper_id_suffix "helper")
  else()
    string(TOLOWER "${variant}" variant_lower)
    set(helper_target "helper_${variant_lower}")
    set(helper_name "${APP_NAME} Helper (${variant})")
    set(helper_id_suffix "helper.${variant}")
  endif()

  add_executable("${helper_target}" MACOSX_BUNDLE src/helper_main.cc)
  target_link_libraries("${helper_target}" PRIVATE cef_dll_wrapper)
  target_link_options("${helper_target}" PRIVATE
    "-F${CEF_FRAMEWORK_DIR}"
    "-Wl,-rpath,@executable_path/../../.."
    "-framework" "Chromium Embedded Framework"
  )
  set_target_properties("${helper_target}" PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "${helper_name}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.cefexperiment.${helper_id_suffix}"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0"
    OUTPUT_NAME "${helper_name}"
  )
  list(APPEND HELPER_TARGETS "${helper_target}")
endforeach()

# ---------------------------------------------------------------------------
# Main application bundle.
# ---------------------------------------------------------------------------
add_executable(${APP_NAME} MACOSX_BUNDLE
  src/main.mm
  src/sidebar.mm
  src/experiment_app.mm
  src/experiment_app.h
)
target_link_libraries(${APP_NAME} PRIVATE cef_dll_wrapper "-framework AppKit")
target_link_options(${APP_NAME} PRIVATE
  "-F${CEF_FRAMEWORK_DIR}"
  "-Wl,-rpath,@executable_path/../Frameworks"
  "-framework" "Chromium Embedded Framework"
)
set_target_properties(${APP_NAME} PROPERTIES
  MACOSX_BUNDLE_BUNDLE_NAME "${APP_NAME}"
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.cefexperiment.app"
  MACOSX_BUNDLE_BUNDLE_VERSION "1.0"
)

# ---------------------------------------------------------------------------
# Bundle assembly: framework + helper apps go into Contents/Frameworks.
# ---------------------------------------------------------------------------
set(APP_BUNDLE "$<TARGET_BUNDLE_DIR:${APP_NAME}>")
set(APP_FRAMEWORKS "${APP_BUNDLE}/Contents/Frameworks")

add_custom_command(TARGET ${APP_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CEF_FRAMEWORK}" "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"
  VERBATIM
)

add_dependencies(${APP_NAME} ${HELPER_TARGETS})

foreach(variant IN LISTS HELPER_VARIANTS)
  if(variant STREQUAL "")
    set(helper_target "helper_base")
    set(helper_name "${APP_NAME} Helper")
  else()
    string(TOLOWER "${variant}" variant_lower)
    set(helper_target "helper_${variant_lower}")
    set(helper_name "${APP_NAME} Helper (${variant})")
  endif()
  add_custom_command(TARGET ${APP_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "$<TARGET_BUNDLE_DIR:${helper_target}>"
      "${APP_FRAMEWORKS}/${helper_name}.app"
    # Helpers reference the framework as @executable_path/../Frameworks/...;
    # this symlink makes that resolve to the main bundle's Frameworks dir.
    COMMAND ${CMAKE_COMMAND} -E create_symlink
      "../.." "${APP_FRAMEWORKS}/${helper_name}.app/Contents/Frameworks"
    VERBATIM
  )
endforeach()

# Ad-hoc codesign everything (helpers first, then the outer bundle).
# Required on modern macOS or the helper processes fail to launch.
add_custom_command(TARGET ${APP_NAME} POST_BUILD
  COMMAND codesign --force --sign - --timestamp=none
    "${APP_FRAMEWORKS}/${APP_NAME} Helper.app"
    "${APP_FRAMEWORKS}/${APP_NAME} Helper (GPU).app"
    "${APP_FRAMEWORKS}/${APP_NAME} Helper (Renderer).app"
    "${APP_FRAMEWORKS}/${APP_NAME} Helper (Plugin).app"
    "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"
    "${APP_BUNDLE}"
  VERBATIM
)
