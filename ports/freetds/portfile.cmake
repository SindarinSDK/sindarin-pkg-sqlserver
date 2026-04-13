vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO FreeTDS/freetds
    REF 0bbd41c816d4cedb391c99a2abaf7623ee56dec5
    SHA512 ce5958c33113f2f1f016ca987794e54e59b2fc3805f66d1d5255e0ec8f03ca28915b86c301d0816c6673dfe957425e2480121480109023d2f9baedd23781d31c
    HEAD_REF Branch-1_4
)

# FreeTDS unconditionally builds src/odbc, src/apps, src/server, src/pool
# which we don't need. Patch the CMakeLists.txt to make them conditional.
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/odbc)"
    "# add_subdirectory(src/odbc)  # disabled by vcpkg overlay"
)
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/apps)"
    "# add_subdirectory(src/apps)  # disabled by vcpkg overlay"
)
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/server)"
    "# add_subdirectory(src/server)  # disabled by vcpkg overlay"
)
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "add_subdirectory(src/pool)"
    "# add_subdirectory(src/pool)  # disabled by vcpkg overlay"
)

# FreeTDS unconditionally links gssapi_krb5 on non-Windows (cmake bug:
# "# TODO check libraries" in CMakeLists.txt). Patch it out since we
# disable Kerberos and don't need GSSAPI.
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "set(lib_NETWORK gssapi_krb5)"
    "set(lib_NETWORK)"
)

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
