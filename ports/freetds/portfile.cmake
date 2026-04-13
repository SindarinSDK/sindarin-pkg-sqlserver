vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO FreeTDS/freetds
    REF 0bbd41c816d4cedb391c99a2abaf7623ee56dec5
    SHA512 ce5958c33113f2f1f016ca987794e54e59b2fc3805f66d1d5255e0ec8f03ca28915b86c301d0816c6673dfe957425e2480121480109023d2f9baedd23781d31c
    HEAD_REF Branch-1_4
)

# ---- Patches for FreeTDS cmake bugs ----

# 1. Disable subdirectories we don't need (odbc, apps, server, pool).
#    FreeTDS builds these unconditionally.
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/odbc)"
    "# add_subdirectory(src/odbc)"
)
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/apps)"
    "# add_subdirectory(src/apps)"
)
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/server)"
    "# add_subdirectory(src/server)"
)
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/pool)"
    "# add_subdirectory(src/pool)"
)

# 2. Remove unconditional gssapi_krb5 linkage on non-Windows.
#    FreeTDS has a "# TODO check libraries" comment — it never checks.
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "set(lib_NETWORK gssapi_krb5)"
    "set(lib_NETWORK)"
)

# 3. FreeTDS always creates both SHARED and STATIC targets for dblib and ctlib,
#    ignoring BUILD_SHARED_LIBS. The SHARED targets fail when linking against
#    static OpenSSL. Comment out the shared targets entirely. Also disable unittests.

# dblib: remove shared target (sybdb), keep static (db-lib)
vcpkg_replace_string("${SOURCE_PATH}/src/dblib/CMakeLists.txt"
    "add_subdirectory(unittests)" "# add_subdirectory(unittests)")
vcpkg_replace_string("${SOURCE_PATH}/src/dblib/CMakeLists.txt"
    "add_library(sybdb SHARED" "# add_library(sybdb_shared SHARED  # disabled for static build\n# ")
vcpkg_replace_string("${SOURCE_PATH}/src/dblib/CMakeLists.txt"
    "target_compile_definitions(sybdb PUBLIC DLL_EXPORT=1)" "# target_compile_definitions(sybdb PUBLIC DLL_EXPORT=1)")
vcpkg_replace_string("${SOURCE_PATH}/src/dblib/CMakeLists.txt"
    "add_dependencies(sybdb encodings_h)" "# add_dependencies(sybdb encodings_h)")
vcpkg_replace_string("${SOURCE_PATH}/src/dblib/CMakeLists.txt"
    "target_link_libraries(sybdb tds" "# target_link_libraries(sybdb tds")

# ctlib: remove shared target (ct), keep static (ct-static)
vcpkg_replace_string("${SOURCE_PATH}/src/ctlib/CMakeLists.txt"
    "add_subdirectory(unittests)" "# add_subdirectory(unittests)")
vcpkg_replace_string("${SOURCE_PATH}/src/ctlib/CMakeLists.txt"
    "add_library(ct SHARED" "# add_library(ct_shared SHARED  # disabled for static build\n# ")
vcpkg_replace_string("${SOURCE_PATH}/src/ctlib/CMakeLists.txt"
    "target_compile_definitions(ct PUBLIC DLL_EXPORT=1)" "# target_compile_definitions(ct PUBLIC DLL_EXPORT=1)")
vcpkg_replace_string("${SOURCE_PATH}/src/ctlib/CMakeLists.txt"
    "target_link_libraries(ct tds" "# target_link_libraries(ct tds")

# tds: disable unittests
vcpkg_replace_string("${SOURCE_PATH}/src/tds/CMakeLists.txt"
    "add_subdirectory(unittests)" "# add_subdirectory(unittests)")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DBUILD_SHARED_LIBS=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DOPENSSL_USE_STATIC_LIBS=ON
        -DENABLE_KRB5=OFF
        -DWITH_OPENSSL=ON
)

vcpkg_cmake_build()
vcpkg_cmake_install()
vcpkg_fixup_pkgconfig()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

file(INSTALL "${SOURCE_PATH}/COPYING.LIB"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}"
     RENAME copyright)
