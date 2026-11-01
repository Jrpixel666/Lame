cmake_minimum_required(VERSION 3.22.1)
project(localdroid)

include(FetchContent)
# Pinned llama.cpp release. Bump the tag to pick up newer model architectures.
FetchContent_Declare(
    llama
    GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
    GIT_TAG        b4600
    GIT_SHALLOW    TRUE
)
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL           OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP          OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE       OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(llama)

add_library(localdroid SHARED llama_jni.cpp)
target_link_libraries(localdroid llama ggml android log)
