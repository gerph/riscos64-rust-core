# riscos64-rust-core agent notes

## Purpose

This repo exists to build and release prebuilt Rust target libraries for RISC OS
64-bit use in the build environment.

The initial proving ground was `../rustexample`.

## What is already known to work

- A minimal `no_std` Rust program can be compiled to an AArch64 ELF object and
  linked into a 64-bit AIF with `riscos64-link`.
- A Cargo-built object can also be linked once `riscos64-mkreloc` accepts
  digit-prefixed file symbol names in `objdump --syms` output.
- 64-bit AIF binaries must be run with `riscos-build-run --64`.
- The existing `libcrt.a` startup and exit model works for Rust `no_std`
  binaries.

## Important pitfalls discovered in rustexample

- Standalone object linking can fail on unresolved `core::panicking::*` helpers
  if code generation emits checked or debug paths without the proper Rust target
  libraries being available.
- A raw `rustc` compile can also mismatch the freshly built `core` crate hash
  against the packaged `libcore`. Validation should compile the test object with
  the same `cargo -Z build-std=core,compiler_builtins` flow as the payload.
- `core::fmt` is too heavy for the current minimal standalone-object approach
  unless the proper Rust target libraries are linked.
- Project-specific code generation flags should not be pushed into the shared
  Cargo config by default.
- Building upstream `compiler_builtins` needs a host C toolchain. In this
  environment that required `build-essential`.
- The current minimal approach is useful for experiments, but it is not the end
  state. The goal here is to ship upstream Rust `core` cleanly enough that those
  workarounds are not needed for ordinary checked `core` code paths.

## Guidance for future agents

- Prefer upstream Rust `core`; do not design a custom replacement library.
- Treat nightly plus `rust-src` as a builder concern, not a user-default
  toolchain change.
- Milestone 2 adds upstream `alloc`, but user programs still provide their own
  `#[global_allocator]`.
- Leave the OS-level Rust interface library out of scope for now.
- Continue treating `libcrt.a` as the startup and exit substrate unless concrete
  Rust support requirements prove otherwise.

## CI inspection

- Agents may inspect CI directly with `gh run list --workflow build.yml`,
  `gh run view <run-id> --log-failed`, and `gh release view` once GitHub CLI
  authentication is available.
- Prefer a one-time `gh auth login` in the environment or a configured
  `GH_TOKEN`.
- `./scripts/ci-status.sh` wraps the common CI inspection commands.
