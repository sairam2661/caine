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

#include <cstdlib>
#include <string>
#include <vector>
#include <filesystem> // Add this at the top for directory checking
#include <iostream>

// --- Helper: Suppress LLVM Diagnostics ---
class NullStream : public llvm::raw_ostream {
public:
  NullStream() : llvm::raw_ostream(true) {}
  void write_impl(const char *, size_t) override {}
  uint64_t current_pos() const override { return 0; }
};

class SilentDiagnosticHandler : public llvm::DiagnosticHandler {
public:
  bool handleDiagnostics(const llvm::DiagnosticInfo &) override {
    return true; 
  }
};

// --- The Fuzz Property ---
void OptimizeNeverCrashes(const std::string &input) {
  if (input.empty()) return;

  llvm::LLVMContext ctx;
  ctx.setDiagnosticHandler(std::make_unique<SilentDiagnosticHandler>());

  auto buf = llvm::MemoryBuffer::getMemBuffer(
      llvm::StringRef(input.data(), input.size()),
      "fuzz_input",
      false);

  auto mod_or_err = llvm::parseBitcodeFile(*buf, ctx);
  if (!mod_or_err) {
    llvm::consumeError(mod_or_err.takeError());
    return;
  }

  std::unique_ptr<llvm::Module> mod = std::move(mod_or_err.get());

  NullStream null_stream;
  if (llvm::verifyModule(*mod, &null_stream)) {
    return;
  }

  llvm::PassBuilder PB;
  llvm::LoopAnalysisManager     LAM;
  llvm::FunctionAnalysisManager FAM;
  llvm::CGSCCAnalysisManager    CGAM;
  llvm::ModuleAnalysisManager   MAM;

  PB.registerModuleAnalyses(MAM);
  PB.registerCGSCCAnalyses(CGAM);
  PB.registerFunctionAnalyses(FAM);
  PB.registerLoopAnalyses(LAM);
  PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

  llvm::ModulePassManager MPM =
      PB.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O2);

  MPM.run(*mod, MAM);
}

std::vector<std::tuple<std::string>> GetSeeds() {
  const char* path_env = std::getenv("SEEDS_DIR");
  
  if (!path_env) {
    std::cout << "[FuzzTest] SEEDS_DIR env var not set. Starting with empty corpus.\n";
    return {};
  }

  std::string path(path_env);
  if (!std::filesystem::exists(path) || !std::filesystem::is_directory(path)) {
    std::cout << "[FuzzTest] Error: Seed directory not found: " << path << "\n";
    return {};
  }

  // Read the files
  auto seeds = fuzztest::ReadFilesFromDirectory(path);
  
  // Confirmation log
  std::cout << "[FuzzTest] Successfully loaded " << seeds.size() 
            << " raw seed files from: " << path << "\n";
            
  return seeds;
}

// --- Registration ---
FUZZ_TEST(LLVMOptimizerFuzz, OptimizeNeverCrashes)
    .WithSeeds(GetSeeds);