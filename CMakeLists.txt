cmake_minimum_required(VERSION 3.15)

if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
    if(DEFINED VCPKG_ROOT AND EXISTS "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
        set(CMAKE_TOOLCHAIN_FILE "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE STRING "Vcpkg toolchain file")
    elseif(DEFINED ENV{VCPKG_ROOT} AND EXISTS "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
        set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE STRING "Vcpkg toolchain file")
    else()
        find_program(VCPKG_EXE vcpkg)
        if(VCPKG_EXE)
            get_filename_component(VCPKG_DIR "${VCPKG_EXE}" DIRECTORY)
            if(EXISTS "${VCPKG_DIR}/scripts/buildsystems/vcpkg.cmake")
                set(CMAKE_TOOLCHAIN_FILE "${VCPKG_DIR}/scripts/buildsystems/vcpkg.cmake" CACHE STRING "Vcpkg toolchain file")
            endif()
        endif()
    endif()
endif()

if(WIN32 OR CYGWIN)
    if(MINGW OR CYGWIN)
        option(BUILD_SHARED_LIBS "Build shared libraries" OFF)
    endif()
    
    if(NOT BUILD_SHARED_LIBS AND MSVC)
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    elseif(MSVC)
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
    endif()
endif()

if(WIN32 AND CMAKE_TOOLCHAIN_FILE MATCHES "vcpkg.cmake")
    if(NOT DEFINED VCPKG_TARGET_TRIPLET)
        if(BUILD_SHARED_LIBS)
            set(VCPKG_TARGET_TRIPLET "x64-windows" CACHE STRING "Vcpkg target triplet")
        else()
            set(VCPKG_TARGET_TRIPLET "x64-windows-static" CACHE STRING "Vcpkg target triplet")
        endif()
        message(STATUS "Vcpkg triplet automatically set to ${VCPKG_TARGET_TRIPLET}")
    else()
        message(STATUS "Vcpkg triplet is user-defined: ${VCPKG_TARGET_TRIPLET}")
    endif()
endif()

project(ffms2 C CXX)

option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(ENABLE_AVISYNTH "Enable AviSynth+ plugin" OFF)
option(ENABLE_DEBUG "Enable debug build" OFF)

file(READ "include/ffms.h" FFMS_HEADER_CONTENT)
string(REGEX MATCH "define FFMS_VERSION \\(\\(([0-9]+) << 24\\) \\| \\(([0-9]+) << 16\\) \\| \\(([0-9]+) << 8\\) \\| ([0-9]+)\\)" _ ${FFMS_HEADER_CONTENT})
set(VERSION_MAJOR ${CMAKE_MATCH_1})
set(VERSION_MINOR ${CMAKE_MATCH_2})
set(VERSION_PATCH ${CMAKE_MATCH_3})
set(VERSION_TWEAK ${CMAKE_MATCH_4})
if(VERSION_TWEAK GREATER 0)
    set(FFMS_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}.${VERSION_TWEAK}")
else()
    set(FFMS_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}")
endif()
message(STATUS "FFMS2 Version: ${FFMS_VERSION}")

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose build type" FORCE)
endif()

add_compile_options(-Wall -Wextra)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(INCLUDE_DIR "${SRC_DIR}/include")

find_package(ZLIB REQUIRED)
find_package(FFMPEG REQUIRED)

file(GLOB CORE_SOURCES
    "src/core/audiosource.cpp"
    "src/core/ffms.cpp"
    "src/core/filehandle.cpp"
    "src/core/indexing.cpp"
    "src/core/track.cpp"
    "src/core/utils.cpp"
    "src/core/videosource.cpp"
    "src/core/videoutils.cpp"
    "src/core/zipfile.cpp"
    "src/vapoursynth/vapoursource4.cpp"
    "src/vapoursynth/vapoursynth4.cpp"
)

add_library(ffms2 ${CORE_SOURCES})

target_include_directories(ffms2 PUBLIC
    $<BUILD_INTERFACE:${INCLUDE_DIR}>
    $<INSTALL_INTERFACE:include>
    PRIVATE
    src/config
    src/core
    src/vapoursynth
    ${FFMPEG_INCLUDE_DIRS}
)

target_compile_definitions(ffms2 PRIVATE
    _FILE_OFFSET_BITS=64
    __STDC_CONSTANT_MACROS
    FFMS_EXPORTS
)

if(NOT BUILD_SHARED_LIBS)
    target_compile_definitions(ffms2 INTERFACE FFMS_STATIC)
endif()

target_link_directories(ffms2 PRIVATE ${FFMPEG_LIBRARY_DIRS})

target_link_libraries(ffms2 PUBLIC ZLIB::ZLIB PRIVATE ${FFMPEG_LIBRARIES})

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    set_target_properties(ffms2 PROPERTIES CXX_VISIBILITY_PRESET hidden)
endif()

if(ENABLE_AVISYNTH)
    set(AVISYNTHPLUS_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../AviSynthPlus/avs_core/include"
        CACHE PATH "Path to the AviSynthPlus 'avs_core/include' directory")

    if(NOT EXISTS "${AVISYNTHPLUS_INCLUDE_DIR}/avisynth.h")
        message(FATAL_ERROR "Avisynth support was enabled, but avisynth.h was not found at the expected location: ${AVISYNTHPLUS_INCLUDE_DIR}\n"
                            "Please ensure the AviSynthPlus repository is in the same parent directory as ffms2, or manually set the AVISYNTHPLUS_INCLUDE_DIR variable.")
    endif()

    message(STATUS "Avisynth support enabled (using headers from ${AVISYNTHPLUS_INCLUDE_DIR})")

    file(GLOB AVISYNTH_SOURCES
        "src/avisynth/avssources.cpp"
        "src/avisynth/avisynth.cpp"
    )
    target_sources(ffms2 PRIVATE ${AVISYNTH_SOURCES})
    target_include_directories(ffms2 PRIVATE src/avisynth ${AVISYNTHPLUS_INCLUDE_DIR})
    target_compile_definitions(ffms2 PRIVATE AVISYNTH)
endif()

add_executable(ffmsindex src/index/ffmsindex.cpp)

target_link_libraries(ffmsindex PRIVATE ffms2)

if(WIN32)
    target_link_options(ffmsindex PRIVATE -municode)
endif()

install(TARGETS ffms2 ffmsindex
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY ${INCLUDE_DIR}/ DESTINATION include)

set(prefix ${CMAKE_INSTALL_PREFIX})
set(exec_prefix "\${prefix}")
set(libdir "\${prefix}/lib")
set(includedir "\${prefix}/include")

if(WIN32 AND NOT MINGW)
    set(ZLIB_LDFLAGS "")
else()
    set(ZLIB_LDFLAGS "-lz")
endif()

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/ffms2.pc.in"
    "${CMAKE_CURRENT_BINARY_DIR}/ffms2.pc"
    @ONLY
)

install(FILES "${CMAKE_CURRENT_BINARY_DIR}/ffms2.pc" DESTINATION lib/pkgconfig)