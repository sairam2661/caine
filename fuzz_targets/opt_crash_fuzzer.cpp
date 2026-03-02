// opt_crash_fuzzer.cpp
//
// Fuzz target: feed arbitrary bytes to the LLVM optimizer and look for
// crashes via ASAN/UBSan instrumentation.
//
// Design notes:
// - Input is raw bytes, attempted to be parsed as LLVM bitcode.
// - Invalid inputs are silently discarded (early return) — Centipede's
//   coverage-guided engine will learn over time to produce valid bitcode
//   by observing which inputs get further into the optimizer.
// - We run the full O2 pipeline. You can narrow this to specific passes
//   later (see the commented alternatives at the bottom).
// - -UNDEBUG is set by fuzztest_setup_fuzzing_flags(), which means all
//   LLVM assert()s and llvm_unreachable()s are live. This is intentional —
//   assertion failures are bugs we want to find.

#include "fuzztest/fuzztest.h"
#include "gtest/gtest.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/IR/DiagnosticHandler.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Passes/OptimizationLevel.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

// ---------------------------------------------------------------------------
// Helper: suppress LLVM's diagnostic output during fuzzing.
// Without this, every malformed-bitcode rejection prints to stderr and
// floods the terminal.
// ---------------------------------------------------------------------------
class NullStream : public llvm::raw_ostream {
public:
  NullStream() : llvm::raw_ostream(/*unbuffered=*/true) {}
  void write_impl(const char *, size_t) override {}
  uint64_t current_pos() const override { return 0; }
};

// Subclass DiagnosticHandler and override handleDiagnostics to drop
// everything. This is the correct API for silencing diagnostics in LLVM 16+.
// The base class default implementation prints to stderr, which floods the
// terminal with "invalid bitcode" noise during fuzzing.
class SilentDiagnosticHandler : public llvm::DiagnosticHandler {
public:
  bool handleDiagnostics(const llvm::DiagnosticInfo &) override {
    return true; // true = "handled", suppresses default printing
  }
};

// ---------------------------------------------------------------------------
// The fuzz property function.
//
// Centipede calls this repeatedly with mutated inputs. The function must:
//   1. Accept any byte sequence without crashing on its own logic.
//   2. Return normally for inputs that don't trigger bugs.
//   3. Crash (via ASAN/assert) for inputs that do trigger bugs — that's a find.
// ---------------------------------------------------------------------------
void OptimizeNeverCrashes(const std::string &input) {
  llvm::LLVMContext ctx;

  ctx.setDiagnosticHandler(std::make_unique<SilentDiagnosticHandler>());

  // --- Parse input as LLVM bitcode ---
  // We use bitcode (binary) rather than text IR for two reasons:
  //   1. Bitcode is more compact, so Centipede's mutations are more efficient.
  //   2. The bitcode parser is itself interesting to fuzz.
  auto buf = llvm::MemoryBuffer::getMemBuffer(
      llvm::StringRef(input.data(), input.size()),
      /*BufferName=*/"fuzz_input",
      /*RequiresNullTerminator=*/false);

  auto mod_or_err = llvm::parseBitcodeFile(*buf, ctx);
  if (!mod_or_err) {
    // Not valid bitcode — discard the error and return.
    // Centipede will still record coverage up to this point, and over time
    // will produce inputs that get past this check.
    llvm::consumeError(mod_or_err.takeError());
    return;
  }

  // parseBitcodeFile returns Expected<std::unique_ptr<Module>>.
  // Move the unique_ptr out so we own it cleanly.
  std::unique_ptr<llvm::Module> mod = std::move(mod_or_err.get());

  // --- Verify IR well-formedness before running passes ---
  // This avoids feeding structurally broken IR to the optimizer, which
  // would cause llvm_unreachable() trips that aren't interesting bugs.
  // Comment this out if you specifically want to fuzz the passes with
  // malformed IR — that can find different classes of bugs.
  NullStream null_stream;
  if (llvm::verifyModule(*mod, &null_stream)) {
    return;
  }

  // --- Set up the pass pipeline ---
  // Using the new PassManager (NPM) API, which is what modern LLVM uses.
  llvm::PassBuilder PB;
  llvm::LoopAnalysisManager     LAM;
  llvm::FunctionAnalysisManager FAM;
  llvm::CGSCCAnalysisManager    CGAM;
  llvm::ModuleAnalysisManager   MAM;

  // Cross-register all the analysis managers so passes can query each other.
  PB.registerModuleAnalyses(MAM);
  PB.registerCGSCCAnalyses(CGAM);
  PB.registerFunctionAnalyses(FAM);
  PB.registerLoopAnalyses(LAM);
  PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

  // Build the full O2 pipeline.
  // Alternatives to try later:
  //   buildPerModuleDefaultPipeline(OptimizationLevel::O1)  -- lighter
  //   buildPerModuleDefaultPipeline(OptimizationLevel::O3)  -- heavier
  llvm::ModulePassManager MPM =
      PB.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O2);

  // Run the pipeline. If this crashes or trips an assert, we found a bug.
  MPM.run(*mod, MAM);

  // If we reach here: no crash, test passes for this input.
}

// ---------------------------------------------------------------------------
// Register with FuzzTest / Centipede.
//
// In unit test mode (default build): runs for a short time with random inputs.
// In fuzzing mode (-DFUZZTEST_FUZZING_MODE=ON): runs indefinitely with
//   coverage-guided mutations via Centipede.
//
// Run a specific test:
//   ./opt_crash_fuzzer --fuzz=LLVMOptimizerFuzz.OptimizeNeverCrashes
// ---------------------------------------------------------------------------
FUZZ_TEST(LLVMOptimizerFuzz, OptimizeNeverCrashes);