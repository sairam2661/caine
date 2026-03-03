#!/bin/bash
# One-time setup: generates fuzztest.bazelrc in the project root.
# Run this before build_bazel.sh.
set -euo pipefail

export PATH="$HOME/bin:$PATH"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Generating fuzztest.bazelrc ==="
cd "${PROJECT_ROOT}"

bazel run @com_google_fuzztest//bazel:setup_configs > fuzztest.bazelrc

echo "=== Generated fuzztest.bazelrc ==="
cat fuzztest.bazelrc