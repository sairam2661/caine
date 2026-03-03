#!/bin/bash
# scripts/build_ip_fuzzer.sh
#
# Builds the fuzz targets against the pre-built instrumented LLVM.
# Run this after scripts/build_llvm.sh has completed.
#
# Two build modes:
#   Unit test mode (default): quick sanity check, no instrumentation.
#   Fuzzing mode:             full coverage+ASAN, runs indefinitely.
#
# Usage:
#   ./scripts/build_ip_fuzzer.sh           # unit test mode (fast, for dev)
#   ./scripts/build_ip_fuzzer.sh --fuzz    # fuzzing mode (for actual fuzzing)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"

FUZZING_MODE=OFF
if [[ "${1:-}" == "--fuzz" ]]; then
    FUZZING_MODE=ON
    BUILD_DIR="${PROJECT_ROOT}/build-fuzz"
fi

echo "=== Building caine ==="
echo "  Project root: ${PROJECT_ROOT}"
echo "  Build dir:    ${BUILD_DIR}"
echo "  Fuzzing mode: ${FUZZING_MODE}"
echo ""

mkdir -p "${BUILD_DIR}"

CC=clang CXX=clang++ cmake \
    -S "${PROJECT_ROOT}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DFUZZTEST_FUZZING_MODE="${FUZZING_MODE}"

ninja -C "${BUILD_DIR}" -j "$(nproc)" opt_crash_fuzzer_centipede

echo ""
echo "=== Build complete ==="
echo "  Binary: ${BUILD_DIR}/fuzz_targets/opt_crash_fuzzer_centipede"
echo ""

if [[ "${FUZZING_MODE}" == "ON" ]]; then
    echo "To start fuzzing, run:"
    echo "  ./scripts/run_fuzzer.sh"
else
    echo "To run unit tests (quick sanity check):"
    echo "  ${BUILD_DIR}/fuzz_targets/opt_crash_fuzzer_centipede"
    echo ""
    echo "To build in fuzzing mode:"
    echo "  ./scripts/build_ip_fuzzer.sh --fuzz"
fi