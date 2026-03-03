#!/bin/bash
# scripts/run_ip_fuzzer.sh
#
# Runs the fuzz target using FuzzTest's built-in Centipede engine.
#
# Prerequisites:
#   1. scripts/build_llvm.sh has been run.
#   2. scripts/build_ip_fuzzer.sh --fuzz has been run.
#   3. (Optional) scripts/seed_corpus.sh has been run to populate seeds/.
#
# Usage:
#   ./scripts/run_ip_fuzzer.sh                 # run indefinitely
#   ./scripts/run_ip_fuzzer.sh --time=3600     # run for 1 hour then stop
#
# Directory roles:
#   seeds/   raw input files (plain bitcode) - READ by Centipede on startup
#   corpus/  FuzzTest-wrapped corpus files   - READ+WRITTEN by Centipede
#
# Centipede reads raw files from FUZZTEST_TESTSUITE_IN_DIR, wraps them in its
# FUZZTESTv1b envelope format, and adds them to the live corpus. Do NOT put
# raw .bc files directly in corpus! - they will be rejected as invalid format.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUZZER_BIN="${PROJECT_ROOT}/build-fuzz/fuzz_targets/opt_crash_fuzzer"
CORPUS_DIR="${PROJECT_ROOT}/corpus"
REPRO_DIR="${PROJECT_ROOT}/crashes"
export SEEDS_DIR="${PROJECT_ROOT}/seeds"

if [[ ! -f "${FUZZER_BIN}" ]]; then
    echo "Error: fuzzer binary not found at ${FUZZER_BIN}"
    echo "Run: ./scripts/build_fuzzer.sh --fuzz"
    exit 1
fi

mkdir -p "${CORPUS_DIR}"
mkdir -p "${SEEDS_DIR}"
mkdir -p "${REPRO_DIR}"

# Parse optional args
FUZZ_FOR=""
for arg in "$@"; do
    case $arg in
        --time=*)   FUZZ_FOR="--fuzz_for=${arg#*=}s" ;;
    esac
done

SEED_COUNT=$(ls "${SEEDS_DIR}" 2>/dev/null | wc -l)

echo "=== Starting LLVM Optimizer Fuzzer ==="
echo "  Binary:  ${FUZZER_BIN}"
echo "  Corpus:  ${CORPUS_DIR} (FuzzTest-wrapped, persisted across runs)"
echo "  Seeds:   ${SEEDS_DIR} (${SEED_COUNT} raw inputs, imported on startup)"
echo "  Time:    ${FUZZ_FOR:-indefinite}"
echo ""
echo "Press Ctrl+C to stop."
echo ""

FUZZTEST_REPRODUCERS_OUT_DIR="${REPRO_DIR}" \
FUZZTEST_TESTSUITE_OUT_DIR="${CORPUS_DIR}" \
exec "${FUZZER_BIN}" \
    --fuzz=LLVMOptimizerFuzz.OptimizeNeverCrashes \
    ${FUZZ_FOR}