cmake_minimum_required(VERSION 3.15)

if(WIN32)
    if(NOT BUILD_SHARED_LIBS)
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    else()
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

set(VERSION_MAJOR 5)
set(VERSION_MINOR 1)
set(VERSION_PATCH 1)
set(VERSION_TWEAK 0)
set(VERSION_SUFFIX "")

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