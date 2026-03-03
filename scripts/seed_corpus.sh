#!/bin/bash
# scripts/seed_corpus.sh
#
# Populates seeds/ with valid LLVM bitcode from LLVM's own test suite.
# These are raw .bc files — Centipede imports them on startup via
# FUZZTEST_TESTSUITE_IN_DIR and wraps them in its FUZZTESTv1b format.
#
# Run this once before starting fuzzing, or whenever you want fresh seeds.
# The fuzzer does not need to be stopped to re-seed.
#
# Usage:
#   ./scripts/seed_corpus.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEEDS_DIR="${PROJECT_ROOT}/seeds"
LLVM_AS="/data/saiva/llvm-project/build-fuzz/bin/llvm-as"
LLVM_DIS="/data/saiva/llvm-project/build-fuzz/bin/llvm-dis"
LLVM_TEST="/data/saiva/llvm-project/llvm/test"

if [[ ! -f "${LLVM_AS}" ]]; then
    echo "Error: llvm-as not found at ${LLVM_AS}"
    echo "Make sure build_llvm.sh has been run with LLVM_BUILD_TOOLS=ON"
    exit 1
fi

mkdir -p "${SEEDS_DIR}"

echo "=== Seeding corpus from LLVM test suite ==="
echo "  Source:  ${LLVM_TEST}"
echo "  Output:  ${SEEDS_DIR}"
echo ""

COUNT=0
FAILED=0

find "${LLVM_TEST}" -name "*.ll" | while read -r f; do
    # Use a hash of the path as filename to avoid collisions from same basename
    name=$(echo "$f" | md5sum | cut -d' ' -f1).bc
    out="${SEEDS_DIR}/${name}"

    # Assemble then verify by disassembling — only keep valid bitcode
    if "${LLVM_AS}" "$f" -o "$out" 2>/dev/null && \
       "${LLVM_DIS}" "$out" -o /dev/null 2>/dev/null; then
        echo -n "."
    else
        rm -f "$out"
        echo -n "x"
    fi
done

echo ""
echo ""
VALID=$(ls "${SEEDS_DIR}"/*.bc 2>/dev/null | wc -l)
echo "=== Seeding complete: ${VALID} valid bitcode files in ${SEEDS_DIR} ==="
echo ""
echo "Now run: ./scripts/run_fuzzer.sh"