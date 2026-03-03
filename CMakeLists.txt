cmake_minimum_required(VERSION 3.20)
project(caine CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ---------------------------------------------------------------------------
# Paths - override via -DFUZZTEST_SRC=... -DLLVM_BUILD_DIR=... if needed
# ---------------------------------------------------------------------------
set(FUZZTEST_SRC      "/data/saiva/fuzztest"                        CACHE PATH "Path to fuzztest source")
set(LLVM_BUILD_DIR    "/data/saiva/llvm-project/build-fuzz"         CACHE PATH "Path to instrumented LLVM build")

# ---------------------------------------------------------------------------
# STEP 1: Add FuzzTest BEFORE any fuzzing flags are set.
#
# Why: fuzztest_setup_fuzzing_flags() (defined in
# fuzztest/cmake/FuzzTestFlagSetup.cmake) sets CMAKE_CXX_FLAGS globally via
# a macro. If FuzzTest's own targets are added after that macro runs, they
# will be compiled with coverage+asan flags, which causes the fuzzer to fuzz
# itself - a documented footgun in the FuzzTest CMake quickstart.
# ---------------------------------------------------------------------------
add_subdirectory(${FUZZTEST_SRC} fuzztest_build)

# ---------------------------------------------------------------------------
# STEP 2: Find the pre-built (instrumented) LLVM.
#
# LLVM is built separately (see scripts/build_llvm.sh) with:
#   -fsanitize-coverage=inline-8bit-counters
#   -fsanitize-coverage=trace-cmp
#   -fsanitize=address
#
# This is intentional: we WANT coverage signal from inside the optimizer
# passes themselves, not just from our thin wrapper. Building LLVM as an
# add_subdirectory here would be problematic because:
#   1. It would apply fuzztest_setup_fuzzing_flags() to LLVM's own build
#      system which doesn't expect those flags.
#   2. Full LLVM build takes 30-60min; pre-building once and reusing is
#      much faster for iteration.
# ---------------------------------------------------------------------------
find_package(LLVM REQUIRED CONFIG
    HINTS "${LLVM_BUILD_DIR}/lib/cmake/llvm"
    NO_DEFAULT_PATH)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION} at ${LLVM_DIR}")
message(STATUS "LLVM include dirs: ${LLVM_INCLUDE_DIRS}")

include_directories(SYSTEM ${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

# ---------------------------------------------------------------------------
# STEP 3: NOW set fuzzing flags.
#
# From FuzzTestFlagSetup.cmake, when FUZZTEST_FUZZING_MODE=ON this adds:
#   -g
#   -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
#   -UNDEBUG                    <-- important: keeps assertions alive
#   -fsanitize=address
#   -fsanitize-coverage=inline-8bit-counters
#   -fsanitize-coverage=trace-cmp
#   -DADDRESS_SANITIZER
#
# Everything defined AFTER this call gets these flags. FuzzTest itself
# (added above) does NOT get them.
# ---------------------------------------------------------------------------
fuzztest_setup_fuzzing_flags()

# ---------------------------------------------------------------------------
# STEP 4: Define fuzz targets
# ---------------------------------------------------------------------------
enable_testing()
include(GoogleTest)

add_subdirectory(fuzz_targets)