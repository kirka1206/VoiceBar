cmake_minimum_required(VERSION 3.24)
project(VoiceBarWhisper LANGUAGES C CXX)

include(FetchContent)

# Keep the ASR implementation and the Metal kernels in one pinned upstream
# build so the C bridge and the runtime library always use the same ABI.
set(GGML_METAL ON CACHE BOOL "Build the Apple Metal backend" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "Embed Metal kernels" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "Avoid an OpenMP runtime dependency" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Link upstream whisper.cpp dependencies statically" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "Do not build upstream tests" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "Do not build upstream examples" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "Do not build upstream server" FORCE)

FetchContent_Declare(
    whisper_cpp
    GIT_REPOSITORY https://github.com/ggml-org/whisper.cpp.git
    GIT_TAG v1.8.2
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(whisper_cpp)

add_library(VoiceBarWhisper SHARED Sources/WhisperBridge/WhisperBridge.cpp)
target_compile_features(VoiceBarWhisper PRIVATE cxx_std_17)
target_link_libraries(VoiceBarWhisper PRIVATE whisper)
set_target_properties(VoiceBarWhisper PROPERTIES
    OUTPUT_NAME VoiceBarWhisper
    MACOSX_RPATH ON
    BUILD_RPATH "@loader_path"
)
