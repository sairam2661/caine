#!/bin/bash
# scripts/build_llvm.sh
#
# Builds LLVM with coverage + ASAN instrumentation so that Centipede gets
# coverage signal from inside the optimizer passes themselves.
#
# This script only needs to be run ONCE (or when you update LLVM).
# The output at $LLVM_BUILD_DIR is consumed by the fuzzer CMakeLists.txt
# via find_package(LLVM).
#
# Runtime: ~30-60min depending on core count and build type.
# Tip: use -DCMAKE_BUILD_TYPE=Release for faster builds during development,
#      switch to RelWithDebInfo when you want readable crash stack traces.

set -euo pipefail

LLVM_SRC="/data/saiva/llvm-project"
LLVM_BUILD="${LLVM_SRC}/build-fuzz"
JOBS=$(nproc)

echo "=== Building LLVM ==="
echo "  Source:    ${LLVM_SRC}"
echo "  Build dir: ${LLVM_BUILD}"
echo "  Jobs:      ${JOBS}"
echo ""

# ---------------------------------------------------------------------------
# Coverage + sanitizer flags for LLVM itself.
#
# Why these specific flags:
#   -fsanitize-coverage=inline-8bit-counters
#     Inserts a counter increment on every edge. Centipede reads these
#     counters to determine which inputs exercise new code paths.
#
#   -fsanitize-coverage=trace-cmp
#     Instruments comparison instructions. Centipede uses this to guide
#     mutations toward satisfying branch conditions (e.g., matching a magic
#     number in the bitcode parser).
#
#   -fsanitize=address
#     Catches memory bugs: buffer overflows, use-after-free, etc.
#     This is the primary bug oracle for the crash-finding target.
#
#   -UNDEBUG (set by LLVM's own -DLLVM_ENABLE_ASSERTIONS=ON)
#     Keeps LLVM's assert() and llvm_unreachable() live.
#     Assertion failures are bugs — we want to find them.
#
#   -g (RelWithDebInfo)
#     Debug symbols for readable crash stack traces.
# ---------------------------------------------------------------------------
COV_FLAGS="-fsanitize-coverage=inline-8bit-counters -fsanitize-coverage=trace-cmp -fsanitize=address"

cmake -S "${LLVM_SRC}/llvm" -B "${LLVM_BUILD}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    \
    `# Adding this to fix build issues` \
    -DLLVM_ENABLE_RTTI=ON \
    -DLLVM_USE_LINKER=lld \
    `# Only build the X86 backend — drastically reduces build time.` \
    `# Add AArch64, RISCV etc. later if you want to fuzz those targets.` \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    \
    `# Only build the LLVM core project. No clang, lld, etc. needed here.` \
    -DLLVM_ENABLE_PROJECTS="" \
    \
    `# Keep assertions alive. This is critical — many optimizer bugs manifest` \
    `# as failed assertions before they cause memory corruption.` \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    \
    `# Apply coverage + ASAN to all LLVM code.` \
    `# We want coverage signal from inside the optimizer passes.` \
    -DCMAKE_C_FLAGS="${COV_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COV_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address" \
    -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address" \
    \
    `# Static libraries are easier to link into the fuzzer binary.` \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLVM_BUILD_LLVM_DYLIB=OFF \
    \
    `# Skip things we don't need — saves significant build time.` \
    -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_BUILD_UTILS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_DOCS=OFF

echo ""
echo "=== CMake configure done. Starting build... ==="
echo ""

# Build only the components we need for the fuzzer.
# This avoids building the entire LLVM (which includes many tools we don't need).
ninja -C "${LLVM_BUILD}" -j "${JOBS}" \
    LLVMCore \
    LLVMIRReader \
    LLVMBitWriter \
    LLVMPasses \
    LLVMAnalysis \
    LLVMTransformUtils \
    LLVMSupport \
    LLVMScalarOpts \
    LLVMipo \
    LLVMVectorize

echo ""
echo "=== LLVM build complete ==="
echo "    Build dir: ${LLVM_BUILD}"
echo "    LLVMConfig.cmake: ${LLVM_BUILD}/lib/cmake/llvm/LLVMConfig.cmake"
echo ""
echo "Next step: run scripts/build_fuzzer.sh"