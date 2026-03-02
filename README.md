# LLVM Optimizer Fuzzer

Coverage-guided fuzzing of the LLVM optimizer using
[FuzzTest/Centipede](https://github.com/google/fuzztest).

## Project Layout

```
llvm-fuzzer/
├── CMakeLists.txt              # Root build file — ordering here is critical
├── fuzz_targets/
│   ├── CMakeLists.txt          # Defines fuzz target executables
│   └── opt_crash_fuzzer.cpp    # Fuzz target: find optimizer crashes
├── scripts/
│   ├── build_llvm.sh           # Step 1: build instrumented LLVM (run once)
│   ├── build_fuzzer.sh         # Step 2: build the fuzz targets
│   └── run_fuzzer.sh           # Step 3: start fuzzing
└── corpus/                     # Created at runtime; Centipede saves corpus here
```

## Quickstart

```bash
# Step 1: Install dependencies
sudo apt install -y clang cmake ninja-build

# Step 2: Build LLVM with coverage + ASAN instrumentation (~30-60min, once)
./scripts/build_llvm.sh

# Step 3: Build the fuzzer in fuzzing mode
./scripts/build_fuzzer.sh --fuzz

# Step 4: Start fuzzing
./scripts/run_fuzzer.sh

# Or with parallel workers:
./scripts/run_fuzzer.sh --jobs=8
```

To do a quick sanity check without full fuzzing instrumentation:
```bash
./scripts/build_fuzzer.sh          # unit test mode (fast)
./build/fuzz_targets/opt_crash_fuzzer
```

## Design Decisions

### Why FuzzTest + Centipede over libFuzzer?

- Centipede is the successor to libFuzzer (from the same original authors).
- Out-of-process execution: target crashes don't kill the fuzzer.
- Scales to distributed fuzzing (multiple machines, many workers) more easily.
- FuzzTest's `FUZZ_TEST` macro is cleaner than `LLVMFuzzerTestOneInput`.
- FuzzTest's domain API will let us generate structured valid LLVM IR later.

### Why is LLVM built separately (not as add_subdirectory)?

`fuzztest_setup_fuzzing_flags()` works as a CMake macro — it modifies
`CMAKE_CXX_FLAGS` globally for everything defined *after* it is called.

The FuzzTest CMakeLists.txt calls `fuzztest_setup_fuzzing_flags()` internally
right after its own `add_subdirectory` calls. If LLVM were added as a
subdirectory of our project *before* FuzzTest, FuzzTest's internal call would
apply coverage flags to LLVM. If added *after*, our call would apply them.
Either way leads to LLVM being built inside our CMake graph, which conflicts
with LLVM's own complex CMake setup.

Pre-building LLVM and consuming it via `find_package(LLVM)` avoids all of
this cleanly, and has the practical benefit of separating the 30-60min LLVM
build from the seconds-long fuzzer build during development.

### Why instrument LLVM itself with coverage flags?

We want Centipede to get coverage signal from *inside* the optimizer passes,
not just from our thin wrapper. If LLVM is built without coverage
instrumentation, Centipede sees almost no edges and has nothing to guide
mutations with — the fuzzer becomes essentially random.

### Why keep `-UNDEBUG` / `LLVM_ENABLE_ASSERTIONS=ON`?

LLVM's optimizer contains hundreds of `assert()` and `llvm_unreachable()`
calls that check invariants the passes rely on. These are bugs we want to
find. A release build with assertions disabled would silently skip past many
of them and continue into undefined behavior territory.

`fuzztest_setup_fuzzing_flags()` sets `-UNDEBUG` on the fuzzer side.
`-DLLVM_ENABLE_ASSERTIONS=ON` in `build_llvm.sh` sets it on the LLVM side.

### Why bitcode as the input format (not text IR)?

- More compact: mutations are more efficient per byte.
- The bitcode parser is itself a fuzzing target.
- Text IR parsing can be added later as a second fuzz target if desired.

## Adding New Fuzz Targets

To add a second target (e.g., for miscompilation detection with Alive2):

1. Add `miscompilation_fuzzer.cpp` to `fuzz_targets/`
2. Add to `fuzz_targets/CMakeLists.txt`:
   ```cmake
   add_executable(miscompilation_fuzzer miscompilation_fuzzer.cpp)
   target_link_libraries(miscompilation_fuzzer PRIVATE ${LLVM_LIBS})
   link_fuzztest(miscompilation_fuzzer)
   gtest_discover_tests(miscompilation_fuzzer)
   ```
3. Run `./scripts/build_fuzzer.sh --fuzz` (LLVM does not need to be rebuilt)
4. Run `./build-fuzz/fuzz_targets/miscompilation_fuzzer --fuzz=<Suite>.<Test>`

## Future Work

- **Structured IR generation**: use FuzzTest's domain API to generate valid
  LLVM IR directly, bypassing the bitcode parser rejection rate.
- **Miscompilation detection**: integrate Alive2 as a second oracle.
- **Per-pass targets**: fuzz individual passes (instcombine, sroa, mem2reg)
  in isolation for faster iteration.
- **Corpus seeding**: seed the corpus from LLVM's own test suite (`llvm/test/`)
  which contains many interesting IR patterns.
- **Distributed fuzzing**: Centipede natively supports distributed workloads
  via shared workdirs.