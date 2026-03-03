#include <cstdint>
#include <cstddef>
#include <memory>

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

class SilentDiagnosticHandler : public llvm::DiagnosticHandler {
public:
  bool handleDiagnostics(const llvm::DiagnosticInfo &) override { return true; }
};

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  llvm::LLVMContext ctx;
  ctx.setDiagnosticHandler(std::make_unique<SilentDiagnosticHandler>());

  auto buf = llvm::MemoryBuffer::getMemBuffer(
      llvm::StringRef(reinterpret_cast<const char*>(data), size),
      "fuzz_input", /*RequiresNullTerminator=*/false);

  auto mod_or_err = llvm::parseBitcodeFile(*buf, ctx);
  if (!mod_or_err) {
    llvm::consumeError(mod_or_err.takeError());
    return 0;
  }

  std::unique_ptr<llvm::Module> mod = std::move(mod_or_err.get());
  if (llvm::verifyModule(*mod, &llvm::errs())) return 0;

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

  return 0;
}