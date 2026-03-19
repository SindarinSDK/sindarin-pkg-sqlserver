cmake_minimum_required(VERSION 3.20)
project(sindarin-sqlserver VERSION 1.0.0 LANGUAGES C)

# Allow version override from command line (e.g., -DSS_VERSION=1.2.3)
if(DEFINED SS_VERSION)
    set(PROJECT_VERSION ${SS_VERSION})
endif()

message(STATUS "Sindarin SQL Server libs version: ${PROJECT_VERSION}")

# Determine platform name for output directory
if(WIN32)
    set(PLATFORM_NAME "windows")
elseif(APPLE)
    set(PLATFORM_NAME "darwin")
else()
    set(PLATFORM_NAME "linux")
endif()

message(STATUS "Building for platform: ${PLATFORM_NAME}")

# Output directory structure: libs/{platform}/
set(LIBS_OUTPUT_DIR "${CMAKE_SOURCE_DIR}/libs/${PLATFORM_NAME}")
set(LIBS_LIB_DIR "${LIBS_OUTPUT_DIR}/lib")
set(LIBS_INCLUDE_DIR "${LIBS_OUTPUT_DIR}/include")

# Create output directories
file(MAKE_DIRECTORY "${LIBS_LIB_DIR}")
file(MAKE_DIRECTORY "${LIBS_INCLUDE_DIR}")

# Detect vcpkg installation directory
# Priority: 1. Manifest mode, 2. VCPKG_ROOT env, 3. Classic mode
if(DEFINED VCPKG_INSTALLED_DIR)
    set(VCPKG_INSTALL_PATH "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}")
    message(STATUS "Using vcpkg manifest mode: ${VCPKG_INSTALL_PATH}")
elseif(DEFINED ENV{VCPKG_ROOT})
    set(VCPKG_INSTALL_PATH "$ENV{VCPKG_ROOT}/installed/${VCPKG_TARGET_TRIPLET}")
    message(STATUS "Using VCPKG_ROOT: ${VCPKG_INSTALL_PATH}")
elseif(EXISTS "${CMAKE_SOURCE_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}")
    set(VCPKG_INSTALL_PATH "${CMAKE_SOURCE_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}")
    message(STATUS "Using local vcpkg_installed: ${VCPKG_INSTALL_PATH}")
elseif(EXISTS "${CMAKE_SOURCE_DIR}/vcpkg/installed/${VCPKG_TARGET_TRIPLET}")
    set(VCPKG_INSTALL_PATH "${CMAKE_SOURCE_DIR}/vcpkg/installed/${VCPKG_TARGET_TRIPLET}")
    message(STATUS "Using vcpkg submodule: ${VCPKG_INSTALL_PATH}")
else()
    message(FATAL_ERROR "Could not find vcpkg installation. Please run 'make build-libs' first.")
endif()

# Verify vcpkg installation
if(NOT EXISTS "${VCPKG_INSTALL_PATH}/lib")
    message(FATAL_ERROR "vcpkg libraries not found at ${VCPKG_INSTALL_PATH}/lib")
endif()

message(STATUS "vcpkg lib directory: ${VCPKG_INSTALL_PATH}/lib")
message(STATUS "vcpkg include directory: ${VCPKG_INSTALL_PATH}/include")
message(STATUS "Output lib directory: ${LIBS_LIB_DIR}")
message(STATUS "Output include directory: ${LIBS_INCLUDE_DIR}")

# Copy all static libraries (.a files)
file(GLOB VCPKG_STATIC_LIBS "${VCPKG_INSTALL_PATH}/lib/*.a")
foreach(LIB ${VCPKG_STATIC_LIBS})
    get_filename_component(LIB_NAME ${LIB} NAME)
    message(STATUS "Copying library: ${LIB_NAME}")
    file(COPY ${LIB} DESTINATION "${LIBS_LIB_DIR}")
endforeach()

# On Windows, also copy any .lib files (import libraries)
if(WIN32)
    file(GLOB VCPKG_IMPORT_LIBS "${VCPKG_INSTALL_PATH}/lib/*.lib")
    foreach(LIB ${VCPKG_IMPORT_LIBS})
        get_filename_component(LIB_NAME ${LIB} NAME)
        message(STATUS "Copying import library: ${LIB_NAME}")
        file(COPY ${LIB} DESTINATION "${LIBS_LIB_DIR}")
    endforeach()
endif()

# Copy all headers
if(EXISTS "${VCPKG_INSTALL_PATH}/include")
    message(STATUS "Copying headers from ${VCPKG_INSTALL_PATH}/include")
    file(COPY "${VCPKG_INSTALL_PATH}/include/" DESTINATION "${LIBS_INCLUDE_DIR}")
endif()

# Copy pkgconfig files if they exist
if(EXISTS "${VCPKG_INSTALL_PATH}/lib/pkgconfig")
    file(MAKE_DIRECTORY "${LIBS_OUTPUT_DIR}/lib/pkgconfig")
    file(COPY "${VCPKG_INSTALL_PATH}/lib/pkgconfig/" DESTINATION "${LIBS_OUTPUT_DIR}/lib/pkgconfig")
    message(STATUS "Copied pkgconfig files")
endif()

# Copy cmake config files if they exist
if(EXISTS "${VCPKG_INSTALL_PATH}/share")
    file(MAKE_DIRECTORY "${LIBS_OUTPUT_DIR}/share")
    file(COPY "${VCPKG_INSTALL_PATH}/share/" DESTINATION "${LIBS_OUTPUT_DIR}/share")
    message(STATUS "Copied cmake config files")
endif()

# Create a version file
file(WRITE "${LIBS_OUTPUT_DIR}/VERSION" "${PROJECT_VERSION}\n")
file(WRITE "${LIBS_OUTPUT_DIR}/PLATFORM" "${PLATFORM_NAME}\n")

# Create a manifest of included libraries
file(GLOB ALL_LIBS "${LIBS_LIB_DIR}/*.a")
set(LIB_MANIFEST "")
foreach(LIB ${ALL_LIBS})
    get_filename_component(LIB_NAME ${LIB} NAME)
    string(APPEND LIB_MANIFEST "${LIB_NAME}\n")
endforeach()
file(WRITE "${LIBS_OUTPUT_DIR}/LIBRARIES.txt" "${LIB_MANIFEST}")

message(STATUS "")
message(STATUS "========================================")
message(STATUS "Sindarin SQL Server libs build complete!")
message(STATUS "Platform: ${PLATFORM_NAME}")
message(STATUS "Output directory: ${LIBS_OUTPUT_DIR}")
message(STATUS "Libraries: ${LIBS_LIB_DIR}")
message(STATUS "Headers: ${LIBS_INCLUDE_DIR}")
message(STATUS "========================================")

add_custom_target(install-libs
    COMMAND ${CMAKE_COMMAND} -E echo "Libraries installed to ${LIBS_OUTPUT_DIR}"
)
