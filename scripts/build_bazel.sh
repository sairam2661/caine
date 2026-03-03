#!/bin/bash
# Builds the fuzz target using Bazel with the fuzztest-experimental config,
# which uses trace-pc-guard,pc-table instrumentation for out-of-process Centipede.
set -euo pipefail

export PATH="$HOME/bin:$PATH"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ ! -f fuzztest.bazelrc ]]; then
    echo "Error: fuzztest.bazelrc not found. Run scripts/setup_bazel.sh first."
    exit 1
fi

echo "=== Building opt_crash_fuzzer (Bazel, fuzztest-experimental) ==="

bazel build \
    --config=fuzztest-experimental \
    --config=asan \
    //:opt_crash_fuzzer

BINARY="$(bazel info bazel-bin)/opt_crash_fuzzer"
echo ""
echo "=== Build complete ==="
echo "  ${BINARY}"