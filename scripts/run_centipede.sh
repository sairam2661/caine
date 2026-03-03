#!/bin/bash
# scripts/run_centipede.sh
#
# Runs the LLVM optimizer fuzzer via the standalone Centipede orchestrator.
#
# Crash-tolerant: when the target crashes, Centipede records the input,
# saves it to workdir/crashes/, and continues fuzzing without stopping.
#
# Prerequisites:
#   1. scripts/build_llvm.sh         — builds instrumented LLVM libs
#   2. scripts/build_fuzzer.sh       — builds opt_crash_fuzzer_centipede
#                                      in build-centipede/
#   3. scripts/seed_corpus.sh        — (optional) populates seeds/
#
# Usage:
#   ./scripts/run_centipede.sh                   # run indefinitely
#   ./scripts/run_centipede.sh --time=3600       # stop after N seconds
#   ./scripts/run_centipede.sh --jobs=4          # override parallelism
#   ./scripts/run_centipede.sh --runs=1000000    # stop after N executions
#   ./scripts/run_centipede.sh --test            # smoke test: 500 runs, then exit
#
# Output directories:
#   workdir/          corpus shards, coverage reports, stats (persistent)
#   workdir/crashes/  inputs that caused crashes (inspect with --repro below)
#   seeds/            raw .bc seed inputs (read-only, fed at startup)
#
# To reproduce a crash after fuzzing:
#   CENTIPEDE_CRASH_ID=<id> ./build-centipede/fuzz_targets/opt_crash_fuzzer_centipede

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CENTIPEDE="${PROJECT_ROOT}/../centipede-bin/centipede"
# Allow override via env var
CENTIPEDE="${CENTIPEDE_BIN:-${CENTIPEDE}}"

TARGET="${PROJECT_ROOT}/build-centipede/fuzz_targets/opt_crash_fuzzer_centipede"
WORKDIR="${PROJECT_ROOT}/workdir"
SEEDS_DIR="${PROJECT_ROOT}/seeds"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if [[ ! -f "${CENTIPEDE}" ]]; then
    echo "Error: centipede binary not found at ${CENTIPEDE}"
    echo "Run: ./scripts/build_centipede.sh"
    exit 1
fi

if [[ ! -f "${TARGET}" ]]; then
    echo "Error: fuzz target not found at ${TARGET}"
    echo "Run: ./scripts/build_fuzzer.sh"
    exit 1
fi

# Verify the binary has the correct instrumentation (trace-pc-guard, NOT 8bit-counters)
if nm "${TARGET}" 2>/dev/null | grep -q "__sanitizer_cov_8bit_counters_init"; then
    # 8bit-counters coming from LLVM libs is okay — check it ALSO has trace-pc-guard
    if ! nm "${TARGET}" 2>/dev/null | grep -q "__sanitizer_cov_trace_pc_guard_init"; then
        echo "Error: ${TARGET} is missing trace-pc-guard instrumentation."
        echo "It was likely built in the wrong build dir (build-fuzz instead of build-centipede)."
        echo "Run: ./scripts/build_fuzzer.sh"
        exit 1
    fi
fi

mkdir -p "${WORKDIR}"
mkdir -p "${SEEDS_DIR}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
JOBS=$(nproc)
NUM_RUNS=""
STOP_AFTER_SECONDS=""
SMOKE_TEST=false

for arg in "$@"; do
    case $arg in
        --jobs=*)   JOBS="${arg#*=}" ;;
        --runs=*)   NUM_RUNS="${arg#*=}" ;;
        --time=*)   STOP_AFTER_SECONDS="${arg#*=}" ;;
        --test)     SMOKE_TEST=true ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--jobs=N] [--runs=N] [--time=SECONDS] [--test]"
            exit 1
            ;;
    esac
done

if [[ "${SMOKE_TEST}" == "true" ]]; then
    NUM_RUNS=500
fi

# ---------------------------------------------------------------------------
# Build the centipede command
# ---------------------------------------------------------------------------
CENTIPEDE_ARGS=(
    "--binary=${TARGET}"
    "--workdir=${WORKDIR}"
    "--j=${JOBS}"
    # Feed raw .bc seed files on startup. Centipede wraps them internally.
    # New interesting inputs found during fuzzing are saved to workdir/corpus.*
    "--corpus_dir=${SEEDS_DIR}"
    # Save crash-triggering inputs here for later reproduction
    # Print a log line every time new coverage is found
    "--log_features_shards=1"
)

if [[ -n "${NUM_RUNS}" ]]; then
    CENTIPEDE_ARGS+=("--num_runs=${NUM_RUNS}")
fi

if [[ -n "${STOP_AFTER_SECONDS}" ]]; then
    CENTIPEDE_ARGS+=("--stop_after_seconds=${STOP_AFTER_SECONDS}")
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
SEED_COUNT=$(ls "${SEEDS_DIR}" 2>/dev/null | wc -l)

echo "=== Starting Centipede LLVM Optimizer Fuzzer ==="
echo "  Target:   ${TARGET}"
echo "  Workdir:  ${WORKDIR}"
echo "  Seeds:    ${SEEDS_DIR} (${SEED_COUNT} files)"
echo "  Jobs:     ${JOBS} parallel workers"
if [[ -n "${NUM_RUNS}" ]]; then
    echo "  Runs:     ${NUM_RUNS}"
elif [[ -n "${STOP_AFTER_SECONDS}" ]]; then
    echo "  Time:     ${STOP_AFTER_SECONDS}s"
else
    echo "  Time:     indefinite (Ctrl+C to stop)"
fi
echo ""
echo "Crash inputs will be saved to: ${WORKDIR}/crashes/"
echo "Coverage reports:              ${WORKDIR}/coverage-report-*.txt"
echo ""

if [[ "${SMOKE_TEST}" == "true" ]]; then
    echo "=== SMOKE TEST MODE (500 runs) ==="
    echo ""
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
exec "${CENTIPEDE}" "${CENTIPEDE_ARGS[@]}"