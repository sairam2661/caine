#!/bin/bash
set -euo pipefail

export PATH="$HOME/bin:$PATH"
FUZZTEST_DIR="/data/saiva/fuzztest"
OUT_DIR="/data/saiva/centipede-bin"

echo "=== Building Centipede with Bazel ==="
cd "${FUZZTEST_DIR}"

bazel build -c opt \
    //centipede:centipede \
    //centipede:centipede_runner_static

mkdir -p "${OUT_DIR}"
cp bazel-bin/centipede/centipede "${OUT_DIR}/"
cp bazel-bin/centipede/libcentipede_runner_static.a "${OUT_DIR}/"
cp centipede/clang-flags.txt "${OUT_DIR}/"

echo "=== Built ==="
echo "  ${OUT_DIR}/centipede"
echo "  ${OUT_DIR}/libcentipede_runner_static.a"