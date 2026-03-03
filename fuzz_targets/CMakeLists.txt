# ---------------------------------------------------------------------------
# Map logical LLVM component names to actual library targets.
# This is the canonical LLVM CMake way — do NOT hardcode -lLLVMCore etc.
# ---------------------------------------------------------------------------
llvm_map_components_to_libnames(LLVM_LIBS
    Core          # Module, Function, BasicBlock, Instruction IR types
    IRReader      # parseIRFile / parseBitcodeFile
    BitWriter     # WriteBitcodeToFile (useful for reproducer output)
    Passes        # PassBuilder, all the standard passes
    Analysis      # Various analysis passes (AA, DominatorTree, etc.)
    TransformUtils # Common utilities used by passes
    Support       # LLVMContext, MemoryBuffer, raw_ostream, error handling
    # Add more as needed, e.g.:
    # Scalar       # Scalar optimization passes (instcombine, mem2reg, etc.)
    # Vectorize    # Loop/SLP vectorizer
    # IPO          # Interprocedural optimizations
)

message(STATUS "LLVM libs for fuzzer: ${LLVM_LIBS}")

# ---------------------------------------------------------------------------
# Target 1: opt_crash_fuzzer
#
# Goal: find crashes in the LLVM optimizer.
# Oracle: ASAN + UBSan — any abort/segfault/sanitizer trip = bug found.
# Input: raw bytes, interpreted as LLVM bitcode. Invalid bitcode is silently
# skipped (early return), so Centipede learns to produce valid bitcode over
# time via coverage feedback.
# ---------------------------------------------------------------------------
add_executable(opt_crash_fuzzer opt_crash_fuzzer.cpp)

target_link_libraries(opt_crash_fuzzer
    PRIVATE
    ${LLVM_LIBS}
)

link_fuzztest(opt_crash_fuzzer)
gtest_discover_tests(opt_crash_fuzzer)

# ---------------------------------------------------------------------------
# Target 2: opt_crash_fuzzer_centipede
#
# Same oracle as opt_crash_fuzzer but uses LLVMFuzzerTestOneInput + the
# Centipede runner library. Run via the standalone centipede binary for
# out-of-process, crash-tolerant, multi-job fuzzing.
# ---------------------------------------------------------------------------
set(CENTIPEDE_RUNNER_LIB "/data/saiva/centipede-bin/libcentipede_runner_static.a")

if(EXISTS "${CENTIPEDE_RUNNER_LIB}")
    add_executable(opt_crash_fuzzer_centipede opt_crash_fuzzer_centipede.cpp)

    target_include_directories(opt_crash_fuzzer_centipede PRIVATE
        ${LLVM_INCLUDE_DIRS}
    )

    target_link_libraries(opt_crash_fuzzer_centipede
        PRIVATE
        ${LLVM_LIBS}
        ${CENTIPEDE_RUNNER_LIB}
        dl rt pthread
    )

    # Centipede requires sancov instrumentation on the target binary.
    # These flags are separate from (and in addition to) the FuzzTest flags
    # set by fuzztest_setup_fuzzing_flags() for opt_crash_fuzzer.
    target_compile_options(opt_crash_fuzzer_centipede PRIVATE
        -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
        -fno-builtin
        -fsanitize-coverage=trace-pc-guard,pc-table,trace-cmp
        -fsanitize=address
        -gline-tables-only
    )
    target_link_options(opt_crash_fuzzer_centipede PRIVATE
        -fsanitize=address
    )

    message(STATUS "Building opt_crash_fuzzer_centipede with Centipede runner")
else()
    message(WARNING "Centipede runner not found at ${CENTIPEDE_RUNNER_LIB} — skipping opt_crash_fuzzer_centipede. Run scripts/build_centipede.sh first.")
endif()