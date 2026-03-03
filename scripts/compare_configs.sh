#!/bin/bash
# compare_configs.sh
# Runs Config 2 (FuzzTest+Centipede) and Config 3 (raw libFuzzer+Centipede)
# in strict cold-start isolation and prints a comparison table.
#
# Isolation guarantees:
#   - Fresh workdirs created immediately before each run (not at script start)
#   - ~/.cache/fuzztest cleared before Config 2
#   - All prior FuzzTest /tmp workdirs removed before Config 2
#   - Log files named with PID + timestamp to avoid cross-run overwrites
#
# Usage:
#   ./compare_configs.sh                  # 5 min each (default)
#   ./compare_configs.sh --duration=300
#   ./compare_configs.sh --duration=600   # 10 min each

set -uo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
PROJECT="/data/saiva/caine"
BINARY_C2="${PROJECT}/bazel-bin/opt_crash_fuzzer"
BINARY_C3="${PROJECT}/build-centipede/fuzz_targets/opt_crash_fuzzer_centipede"
CENTIPEDE="/data/saiva/centipede-bin/centipede"
SEEDS="${PROJECT}/seeds"
JOBS=$(nproc)
DURATION=300

for arg in "$@"; do
  case $arg in
    --duration=*) DURATION="${arg#*=}" ;;
  esac
done

FUZZ_FOR="${DURATION}s"
RUN_ID="$$_$(date +%Y%m%d_%H%M%S)"
LOG_C2="/tmp/compare_c2_${RUN_ID}.log"
LOG_C3="/tmp/compare_c3_${RUN_ID}.log"

# Centipede uses --stop_at with ISO-8601 timestamp
compute_stop_at() {
  date -u -d "+${DURATION} seconds" '+%Y-%m-%dT%H:%M:%SZ'
}

# ── Preflight ────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Config 2 vs Config 3 — Cold-Start Comparison           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Run ID   : ${RUN_ID}"
echo "  Duration : ${DURATION}s per config (sequential)"
echo "  Jobs     : ${JOBS}"
echo "  Seeds    : ${SEEDS}"
echo ""

for f in "${BINARY_C2}" "${BINARY_C3}" "${CENTIPEDE}"; do
  if [[ ! -f "${f}" ]]; then
    echo "ERROR: missing binary: ${f}"; exit 1
  fi
done
[[ -d "${SEEDS}" ]] || { echo "ERROR: seeds not found: ${SEEDS}"; exit 1; }

SEED_COUNT=$(ls "${SEEDS}" | wc -l)
echo "  Seed files : ${SEED_COUNT}"
echo "  C3 log     : ${LOG_C3}"
echo "  C2 log     : ${LOG_C2}"
echo ""

# ── Parse helpers ─────────────────────────────────────────────────────────────
parse_metric() {
  local log="$1" metric="$2"
  grep "end-fuzz" "${log}" | grep "\[S0\." | tail -1 \
    | grep -oP "${metric}: \K[0-9]+" || echo "N/A"
}
parse_crashes() {
  grep "end-fuzz" "${log:-$1}" | grep "\[S0\." | tail -1 \
    | grep -oP "crash: \K[0-9]+" || echo "0"
}

# ── RUN CONFIG 3 ──────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶  CONFIG 3: raw LLVMFuzzerTestOneInput + external Centipede"
echo "   Seeds: raw .bc files via --corpus_dir"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Fresh workdir created HERE, immediately before the run
WORKDIR_C3=$(mktemp -d)
echo "  Workdir: ${WORKDIR_C3}"
echo ""

# Copy frozen seeds to writable temp dir — Centipede writes back to corpus_dir
SEEDS_C3=$(mktemp -d)
cp "${SEEDS}"/* "${SEEDS_C3}/"
echo "  Seeds copied to: ${SEEDS_C3} ($(ls ${SEEDS_C3} | wc -l) files)"
echo ""

C3_START=$(date +%s)

"${CENTIPEDE}" \
  --binary="${BINARY_C3}" \
  --workdir="${WORKDIR_C3}" \
  --corpus_dir="${SEEDS_C3}" \
  --j="${JOBS}" \
  --stop_at="$(compute_stop_at)" \
  2>&1 | tee "${LOG_C3}" \
  | { grep --line-buffered -E "init-done|new-feature|end-fuzz|ReportCrash" || true; } \
  | while IFS= read -r line; do
      echo "  [$(date +%H:%M:%S)] ${line}"
    done || true

C3_END=$(date +%s)
C3_ELAPSED=$(( C3_END - C3_START ))
echo ""; echo "  Config 3 wall time: ${C3_ELAPSED}s"; echo ""

# ── ISOLATION RESET ───────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Resetting state for cold-start Config 2..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. FuzzTest default corpus cache
rm -rf ~/.cache/fuzztest/opt_crash_fuzzer 2>/dev/null || true
echo "  ✓ ~/.cache/fuzztest/opt_crash_fuzzer cleared"

# 2. Any prior FuzzTest /tmp workdirs (contain corpus shards from previous runs)
for d in /tmp/tmp.*/opt_crash_fuzzer; do
  [[ -d "${d}" ]] || continue
  parent=$(dirname "${d}")
  if [[ "${parent}" != "${WORKDIR_C3}" ]]; then
    rm -rf "${parent}" && echo "  ✓ Removed: ${parent}"
  fi
done

# 3. fuzztest_workdir_* dirs
rm -rf /tmp/fuzztest_workdir_* 2>/dev/null || true
echo "  ✓ /tmp/fuzztest_workdir_* cleared"
echo ""

# ── RUN CONFIG 2 ──────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶  CONFIG 2: FUZZ_TEST + FuzzTest internal Centipede"
echo "   Seeds: via SEEDS_DIR env var → GetSeeds()"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Fresh workdir created HERE, immediately before the run
WORKDIR_C2=$(mktemp -d)
echo "  Workdir: ${WORKDIR_C2}"
echo ""

C2_START=$(date +%s)

SEEDS_DIR="${SEEDS}" \
"${BINARY_C2}" \
  --fuzz=LLVMOptimizerFuzz.OptimizeNeverCrashes \
  --corpus_database="${WORKDIR_C2}" \
  --jobs="${JOBS}" \
  --fuzz_for="${FUZZ_FOR}" \
  --continue_after_crash=true \
  --time_limit_per_input=5s \
  2>&1 | tee "${LOG_C2}" \
  | { grep --line-buffered -E "init-done|new-feature|end-fuzz|More seeds|CRASH LOG|ReportCrash" || true; } \
  | while IFS= read -r line; do
      echo "  [$(date +%H:%M:%S)] ${line}"
    done || true

C2_END=$(date +%s)
C2_ELAPSED=$(( C2_END - C2_START ))
echo ""; echo "  Config 2 wall time: ${C2_ELAPSED}s"; echo ""

# ── RESULTS TABLE ─────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  FINAL RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

C3_COV=$(parse_metric   "${LOG_C3}" "cov")
C3_FT=$(parse_metric    "${LOG_C3}" "ft")
C3_CMP=$(parse_metric   "${LOG_C3}" "cmp")
C3_CORP=$(grep "end-fuzz" "${LOG_C3}" | grep "\[S0\." | tail -1 \
  | grep -oP "corp: \K[0-9]+" || echo "N/A")
C3_CRASH=$(grep "end-fuzz" "${LOG_C3}" | grep "\[S0\." | tail -1 \
  | grep -oP "crash: \K[0-9]+" || echo "0")
C3_EPS=$(parse_metric   "${LOG_C3}" "exec/s")
C3_INIT_COV=$(grep "init-done" "${LOG_C3}" | head -1 \
  | grep -oP "cov: \K[0-9]+" || echo "N/A")
C3_INIT_CORP=$(grep "init-done" "${LOG_C3}" | head -1 \
  | grep -oP "corp: \K[0-9]+/[0-9]+" || echo "N/A")

C2_COV=$(parse_metric   "${LOG_C2}" "cov")
C2_FT=$(parse_metric    "${LOG_C2}" "ft")
C2_CMP=$(parse_metric   "${LOG_C2}" "cmp")
C2_CORP=$(grep "end-fuzz" "${LOG_C2}" | grep "\[S0\." | tail -1 \
  | grep -oP "corp: \K[0-9]+" || echo "N/A")
C2_CRASH=$(grep "end-fuzz" "${LOG_C2}" | grep "\[S0\." | tail -1 \
  | grep -oP "crash: \K[0-9]+" || echo "0")
C2_EPS=$(parse_metric   "${LOG_C2}" "exec/s")
C2_SEEDS=$(grep -oP "Number of input seeds available: \K[0-9]+" "${LOG_C2}" \
  | head -1 || echo "N/A")
C2_INIT_COV=$(grep "init-done" "${LOG_C2}" | head -1 \
  | grep -oP "cov: \K[0-9]+" || echo "N/A")

printf "  %-30s  %-14s  %-14s\n" "Metric" "Config 3" "Config 2"
printf "  %-30s  %-14s  %-14s\n" "──────────────────────────────" "──────────────" "──────────────"
printf "  %-30s  %-14s  %-14s\n" "Seeds loaded"                  "${C3_INIT_CORP}" "${C2_SEEDS}"
printf "  %-30s  %-14s  %-14s\n" "Coverage at init (cov)"        "${C3_INIT_COV}"  "${C2_INIT_COV}"
printf "  %-30s  %-14s  %-14s\n" "── after ${DURATION}s ──"      "──────────────"  "──────────────"
printf "  %-30s  %-14s  %-14s\n" "Edge coverage (cov)"           "${C3_COV}"       "${C2_COV}"
printf "  %-30s  %-14s  %-14s\n" "Total features (ft)"           "${C3_FT}"        "${C2_FT}"
printf "  %-30s  %-14s  %-14s\n" "CMP features"                  "${C3_CMP}"       "${C2_CMP}"
printf "  %-30s  %-14s  %-14s\n" "Corpus size"                   "${C3_CORP}"      "${C2_CORP}"
printf "  %-30s  %-14s  %-14s\n" "Crashes found"                 "${C3_CRASH}"     "${C2_CRASH}"
printf "  %-30s  %-14s  %-14s\n" "Exec/s (shard 0)"              "${C3_EPS}"       "${C2_EPS}"
printf "  %-30s  %-14s  %-14s\n" "Wall time (s)"                 "${C3_ELAPSED}"   "${C2_ELAPSED}"
echo ""

# ── COVERAGE GROWTH ───────────────────────────────────────────────────────────
echo "  Coverage growth (shard 0, sampled every 5th new-feature event):"
echo ""
printf "  %-8s  %-12s  %-12s\n" "Sample" "C3 cov" "C2 cov"
printf "  %-8s  %-12s  %-12s\n" "────────" "────────────" "────────────"

mapfile -t C3_COVS < <(grep "new-feature" "${LOG_C3}" | grep "\[S0\." \
  | grep -oP "cov: \K[0-9]+" | awk 'NR%5==0' | head -12)
mapfile -t C2_COVS < <(grep "new-feature" "${LOG_C2}" | grep "\[S0\." \
  | grep -oP "cov: \K[0-9]+" | awk 'NR%5==0' | head -12)

MAX=${#C3_COVS[@]}
(( ${#C2_COVS[@]} > MAX )) && MAX=${#C2_COVS[@]}

for (( i=0; i<MAX; i++ )); do
  c3_val="${C3_COVS[$i]:-—}"
  c2_val="${C2_COVS[$i]:-—}"
  printf "  %-8s  %-12s  %-12s\n" "$((( i+1 )*5))" "${c3_val}" "${c2_val}"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Logs:  C3=${LOG_C3}  C2=${LOG_C2}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""