#!/bin/bash
# scripts/run_fuzzer.sh
#
# Runs the crash-finding fuzz target using Centipede (via FuzzTest).
#
# Prerequisites:
#   1. scripts/build_llvm.sh has been run.
#   2. scripts/build_fuzzer.sh --fuzz has been run.
#
# Usage:
#   ./scripts/run_fuzzer.sh                    # run indefinitely
#   ./scripts/run_fuzzer.sh --jobs=8           # run with 8 parallel workers
#   ./scripts/run_fuzzer.sh --time=3600        # run for 1 hour
#
# The fuzzer saves its corpus to ./corpus/ and resumes from it on restart.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUZZER_BIN="${PROJECT_ROOT}/build-fuzz/fuzz_targets/opt_crash_fuzzer"
CORPUS_DIR="${PROJECT_ROOT}/corpus"

if [[ ! -f "${FUZZER_BIN}" ]]; then
    echo "Error: fuzzer binary not found at ${FUZZER_BIN}"
    echo "Run: ./scripts/build_fuzzer.sh --fuzz"
    exit 1
fi

mkdir -p "${CORPUS_DIR}"

# Parse optional args
JOBS=1
TIME_LIMIT=""
for arg in "$@"; do
    case $arg in
        --jobs=*)   JOBS="${arg#*=}" ;;
        --time=*)   TIME_LIMIT="--fuzz_time=${arg#*=}" ;;
    esac
done

echo "=== Starting LLVM Optimizer Fuzzer ==="
echo "  Binary:  ${FUZZER_BIN}"
echo "  Corpus:  ${CORPUS_DIR}"
echo "  Jobs:    ${JOBS}"
echo "  Time:    ${TIME_LIMIT:-indefinite}"
echo ""
echo "Press Ctrl+C to stop. Corpus is saved incrementally."
echo ""

# FuzzTest/Centipede flags:
#   --fuzz=<suite>.<test>  : which fuzz test to run
#   --corpus_database=     : where Centipede saves/loads the corpus
#   --jobs=                : parallel fuzzing workers
#
# Note: when FUZZTEST_FUZZING_MODE=ON, the binary uses Centipede as its
# engine. The --fuzz flag selects which FUZZ_TEST to run.
exec "${FUZZER_BIN}" \
    --fuzz=LLVMOptimizerFuzz.OptimizeNeverCrashes \
    --corpus_database="${CORPUS_DIR}" \
    --jobs="${JOBS}" \
    ${TIME_LIMIT}