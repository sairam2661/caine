"""Module extension to configure the llvm-project repository."""

load("@bazel_tools//tools/build_defs/repo:local.bzl", "new_local_repository")
load("@llvm-project-overlay//:configure.bzl", "llvm_configure")

def _llvm_configure_ext_impl(module_ctx):
    new_local_repository(
        name = "llvm-raw",
        build_file_content = "# empty",
        path = "/data/saiva/llvm-project",
    )
    llvm_configure(
        name = "llvm-project",
        targets = ["X86", "AArch64"],
    )

llvm_configure_ext = module_extension(
    implementation = _llvm_configure_ext_impl,
)