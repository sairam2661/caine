#!/bin/bash
# Run the LLVM optimizer fuzzer via the standalone Centipede orchestrator.
# Uses the Bazel-built binary (fuzztest-experimental config).
# Crashes are recorded and fuzzing continues — safe for 24h experiments.
#
# Usage:
#   ./scripts/run_centipede_bazel.sh
#   ./scripts/run_centipede_bazel.sh --jobs=32
#   ./scripts/run_centipede_bazel.sh --time=86400   # 24 hours

set -euo pipefail

export PATH="$HOME/bin:$PATH"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CENTIPEDE="/data/saiva/centipede-bin/centipede"
TARGET="$(cd "${PROJECT_ROOT}" && bazel info bazel-bin)/opt_crash_fuzzer"
WORKDIR="${PROJECT_ROOT}/workdir-centipede"
SEEDS_DIR="${PROJECT_ROOT}/seeds"

if [[ ! -f "${CENTIPEDE}" ]]; then
    echo "Error: centipede not found. Run scripts/build_centipede.sh"
    exit 1
fi
if [[ ! -f "${TARGET}" ]]; then
    echo "Error: target not found. Run scripts/build_bazel.sh"
    exit 1
fi

mkdir -p "${WORKDIR}"

JOBS=$(nproc)
TIME_LIMIT=""
for arg in "$@"; do
    case $arg in
        --jobs=*)  JOBS="${arg#*=}" ;;
        --time=*)  TIME_LIMIT="--stop_after_n_seconds=${arg#*=}" ;;
    esac
done

echo "=== Starting Centipede (out-of-process, crash-tolerant) ==="
echo "  Target:  ${TARGET}"
echo "  Workdir: ${WORKDIR}"
echo "  Seeds:   ${SEEDS_DIR}"
echo "  Jobs:    ${JOBS}"
echo ""

exec "${CENTIPEDE}" \
    --binary="${TARGET} --fuzz=LLVMOptimizerFuzz.OptimizeNeverCrashes" \
    --workdir="${WORKDIR}" \
    --corpus_dir="${SEEDS_DIR}" \
    --j="${JOBS}" \
    --save_corpus_to_local_dir="${WORKDIR}/corpus" \
    ${TIME_LIMIT}