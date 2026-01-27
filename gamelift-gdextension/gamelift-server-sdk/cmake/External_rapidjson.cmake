# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Download rapidjson header files and install them to the default
# include path: ${GameLiftServerSdk_INSTALL_PREFIX}/include
ExternalProject_Add( rapidjson
    PREFIX "rapidjson"
    GIT_REPOSITORY "https://github.com/Tencent/rapidjson.git"
    GIT_TAG v1.1.0
    PATCH_COMMAND
        ${CMAKE_COMMAND} -E echo "Patching rapidjson CMakeLists.txt for modern CMake" && \
        cd ${CMAKE_CURRENT_BINARY_DIR}/rapidjson/src/rapidjson && \
        sed -i.bak -E 's/cmake_minimum_required\(VERSION ([0-9]+(\.[0-9]+)?)\)/cmake_minimum_required(VERSION 3.5...3.30)/g' CMakeLists.txt && \
        sed -i.bak -E 's/CMAKE_MINIMUM_REQUIRED\(VERSION ([0-9]+(\.[0-9]+)?)\)/CMAKE_MINIMUM_REQUIRED(VERSION 3.5...3.30)/g' CMakeLists.txt
    UPDATE_COMMAND ""
    BUILD_COMMAND ""
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    CMAKE_ARGS
        -DRAPIDJSON_BUILD_TESTS=OFF
        -DRAPIDJSON_BUILD_DOC=OFF
        -DRAPIDJSON_BUILD_EXAMPLES=OFF
        -DDOC_INSTALL_DIR=${CMAKE_CURRENT_BINARY_DIR}/rapidjson/doc
        -DLIB_INSTALL_DIR=${CMAKE_CURRENT_BINARY_DIR}/rapidjson/lib
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    CMAKE_CACHE_ARGS
        ${GameLiftServerSdk_DEFAULT_ARGS}
)
