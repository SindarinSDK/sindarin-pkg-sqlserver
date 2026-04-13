vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO FreeTDS/freetds
    REF 0bbd41c816d4cedb391c99a2abaf7623ee56dec5
    SHA512 ce5958c33113f2f1f016ca987794e54e59b2fc3805f66d1d5255e0ec8f03ca28915b86c301d0816c6673dfe957425e2480121480109023d2f9baedd23781d31c
    HEAD_REF Branch-1_4
)

# ---- Fix FreeTDS cmake for static-only builds ----
# FreeTDS has several cmake bugs that prevent clean static builds:
# 1. Unconditionally links gssapi_krb5 on non-Windows
# 2. Always builds src/odbc, src/apps, src/server, src/pool
# 3. Always creates SHARED targets alongside STATIC (breaks with static OpenSSL)
# 4. Always builds unittests
#
# We fix these by rewriting the affected CMakeLists.txt files.

# Fix root CMakeLists.txt: remove gssapi_krb5 and unwanted subdirectories
file(READ "${SOURCE_PATH}/CMakeLists.txt" _root_cmake)
string(REPLACE "set(lib_NETWORK gssapi_krb5)" "set(lib_NETWORK)" _root_cmake "${_root_cmake}")
string(REPLACE "add_subdirectory(src/odbc)" "# add_subdirectory(src/odbc)" _root_cmake "${_root_cmake}")
string(REPLACE "add_subdirectory(src/apps)" "# add_subdirectory(src/apps)" _root_cmake "${_root_cmake}")
string(REPLACE "add_subdirectory(src/server)" "# add_subdirectory(src/server)" _root_cmake "${_root_cmake}")
string(REPLACE "add_subdirectory(src/pool)" "# add_subdirectory(src/pool)" _root_cmake "${_root_cmake}")
file(WRITE "${SOURCE_PATH}/CMakeLists.txt" "${_root_cmake}")

# Rewrite dblib/CMakeLists.txt: static only, no unittests
file(WRITE "${SOURCE_PATH}/src/dblib/CMakeLists.txt" [=[
if(WIN32)
    set(win_SRCS winmain.c dblib.def dbopen.c)
endif()

add_library(db-lib STATIC
    dblib.c dbutil.c rpc.c bcp.c xact.c dbpivot.c buffering.h
    ${win_SRCS}
)
add_dependencies(db-lib encodings_h)
target_link_libraries(db-lib tds replacements tdsutils ${lib_NETWORK} ${lib_BASE})

INSTALL(TARGETS db-lib
    PUBLIC_HEADER DESTINATION include
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
]=])

# Rewrite ctlib/CMakeLists.txt: static only, no unittests
file(WRITE "${SOURCE_PATH}/src/ctlib/CMakeLists.txt" [=[
set(static_lib_name ct)
if(WIN32)
    set(win_SRCS winmain.c ctlib.def)
    set(static_lib_name libct)
endif()

add_library(ct-static STATIC
    ct.c cs.c blk.c ctutil.c
    ${win_SRCS}
)
SET_TARGET_PROPERTIES(ct-static PROPERTIES OUTPUT_NAME ${static_lib_name})
target_link_libraries(ct-static tds replacements tdsutils ${lib_NETWORK} ${lib_BASE})

INSTALL(TARGETS ct-static
    PUBLIC_HEADER DESTINATION include
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
]=])

# Rewrite tds/CMakeLists.txt: remove unittests reference
file(READ "${SOURCE_PATH}/src/tds/CMakeLists.txt" _tds_cmake)
string(REPLACE "add_subdirectory(unittests)" "# add_subdirectory(unittests)" _tds_cmake "${_tds_cmake}")
file(WRITE "${SOURCE_PATH}/src/tds/CMakeLists.txt" "${_tds_cmake}")

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

file(INSTALL "${SOURCE_PATH}/COPYING_LIB.txt"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}"
     RENAME copyright)
