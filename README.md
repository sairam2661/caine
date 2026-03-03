# LLVM Optimizer Fuzzer

Coverage-guided, crash-tolerant fuzzing of the LLVM O2 optimizer pipeline
using Centipede as the orchestrator.

---

## Overview

Two fuzzing configurations are maintained. Both run the target **out-of-process**
via Centipede's persistent mode — one crash does not stop fuzzing.

| | Config 3 | Config 2 |
|---|---|---|
| **Binary** | `build-centipede/fuzz_targets/opt_crash_fuzzer_centipede` | `bazel-bin/opt_crash_fuzzer` |
| **Build** | CMake | Bazel |
| **Centipede** | External binary | Embedded in FuzzTest runtime |
| **Mutations** | Byte-level (+ `LLVMFuzzerCustomMutator` for IR-level) | Byte-level (+ `ArbitraryLLVMModule()` domain when implemented) |
| **Crash output** | Raw crashing bytes | Minimized input + regression test draft + assertion message |
| **Steady exec/s** | ~1,000–2,000/shard | ~1,000–1,400/shard (drops during crash triage) |
| **Use when** | Max throughput, structured mutations via custom mutator | Need clean crash reports and regression tests |

---

## Directory Layout

```
fuzz_targets/
  opt_crash_fuzzer.cpp            # Config 2 source (FUZZ_TEST macro)
  opt_crash_fuzzer_centipede.cpp  # Config 3 source (LLVMFuzzerTestOneInput)

build-centipede/                  # Config 3 CMake build output
  fuzz_targets/opt_crash_fuzzer_centipede

bazel-bin/                        # Config 2 Bazel build output (symlink)
  opt_crash_fuzzer

seeds-frozen/                     # 289 original .bc seeds — never modify
seeds/                            # live corpus, grows during fuzzing runs

scripts/
  compare_configs.sh              # head-to-head comparison script
  run_centipede.sh                # long-running Config 3 script

MODULE.bazel                      # Bazel deps
llvm_ext.bzl                      # LLVM module extension for Bazel
CMakeLists.txt                    # CMake build
fuzztest.bazelrc                  # Bazel flags for FuzzTest + ASAN
```

---

## Build

### Config 3 (CMake)
```bash
cd /data/saiva/caine/build-centipede
cmake --build . --target opt_crash_fuzzer_centipede -j$(nproc)
```

### Config 2 (Bazel)
```bash
cd /data/saiva/caine
bazel build -c opt \
    --config=fuzztest-experimental \
    --config=asan \
    //:opt_crash_fuzzer
```

---

## Run

### Config 3
```bash
/data/saiva/centipede-bin/centipede \
    --binary=build-centipede/fuzz_targets/opt_crash_fuzzer_centipede \
    --workdir=/data/saiva/caine/workdir-c3 \
    --corpus_dir=/data/saiva/caine/seeds-frozen \
    --j=$(nproc) \
    --stop_at="$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')"
```

Crashes saved to `workdir-c3/crashes.*` as raw bytes.

### Config 2
```bash
SEEDS_DIR=/data/saiva/caine/seeds-frozen \
bazel-bin/opt_crash_fuzzer \
    --fuzz=LLVMOptimizerFuzz.OptimizeNeverCrashes \
    --corpus_database=/data/saiva/caine/corpus-db \
    --jobs=$(nproc) \
    --fuzz_for=3600s \
    --continue_after_crash=true \
    --time_limit_per_input=5s
```

Crashes saved to `corpus-db/opt_crash_fuzzer/LLVMOptimizerFuzz.OptimizeNeverCrashes/crashing/`
with minimized inputs and regression test drafts in the log.

### Compare both (cold start)
```bash
./scripts/compare_configs.sh --duration=300   # 5 min each
./scripts/compare_configs.sh --duration=600   # 10 min each
```

---

## Crash Reports

### Config 3
Raw crashing bytes only. To see the assertion:
```bash
/data/saiva/caine/build-centipede/fuzz_targets/opt_crash_fuzzer_centipede \
    < workdir-c3/crashes.000000/<hash> 2>&1 | grep "Assertion"
```

### Config 2
FuzzTest logs contain for each crash:
- Assertion message and file location
- Minimized input as C++ string literal
- Ready-to-use regression test draft
- Stack trace

Extract all unique assertions from a run:
```bash
grep "CRASH LOG:.*failed\." <logfile> \
    | grep -oP "Assertion.*failed\." \
    | sort -u
```

Replay a saved crash:
```bash
FUZZTEST_REPLAY=corpus-db/opt_crash_fuzzer/LLVMOptimizerFuzz.OptimizeNeverCrashes/crashing/<hash> \
bazel-bin/opt_crash_fuzzer \
    --gtest_filter=LLVMOptimizerFuzz.OptimizeNeverCrashes
```

---

## Adding Structured Mutations

Both configs support IR-level mutation. Choose based on your tool's interface:

### In-memory (`llvm::Module*`) → Config 3 custom mutator
Add to `fuzz_targets/opt_crash_fuzzer_centipede.cpp`:
```cpp
extern "C" size_t LLVMFuzzerCustomMutator(
    uint8_t* data, size_t size, size_t max_size, unsigned int seed) {
  auto M = parseBitcodeToModule(data, size);
  if (!M) return LLVMFuzzerMutate(data, size, max_size);
  YourMutationTool::mutate(*M, seed);
  return serializeModule(*M, data, max_size);
}
```

### File-based (`*.ll`) → offline seed expansion
```bash
for bc in seeds-frozen/*.bc; do
    your-mutation-tool ${bc} --output-dir=seeds-expanded/
done
# Use seeds-expanded/ as corpus_dir
```

### Typed domain → Config 2 (future)
Implement `ArbitraryLLVMModule()` domain in `opt_crash_fuzzer.cpp` to get
FuzzTest's mutation coverage tracking and corpus prioritization.

---

## Key External Paths

| What | Path |
|---|---|
| External Centipede | `/data/saiva/centipede-bin/centipede` |
| LLVM source | `/data/saiva/llvm-project/` |
| FuzzTest source | `/data/saiva/fuzztest/` |
| LLVM Bazel overlay patch | `/data/saiva/llvm-project/utils/bazel/configure.bzl` |

---

## Notes

- `seeds-frozen/` must never be used as a write target — always copy before passing
  to Centipede's `--corpus_dir` (it writes back to that directory).
- Config 2 requires `SEEDS_DIR` env var to load seeds. Without it, only 32
  random FuzzTest-generated seeds are used.
- Bazel build takes ~800s clean. Incremental rebuilds are fast.
- The Bazel LLVM overlay required three patches to work as a dependency
  (see handoff doc for details).