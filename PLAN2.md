# Plan: Milestone 2 `alloc` support in `riscos64-rust-core`

## Summary

Extend `riscos64-rust-core` in place to add milestone 2 support for upstream Rust `alloc`, while keeping milestone 1 `core` support available as a separate build target.

The implementation should keep the same target triple (`aarch64-unknown-none`), the same startup/exit model (`libcrt.a` + Rust `main`), and the same offline-install payload model. `alloc` will be built from upstream source and packaged alongside `core` and `compiler_builtins`. User programs will still provide their own `#[global_allocator]`; this milestone does not introduce a reusable allocator crate into the sysroot.

For allocator policy, use the existing C runtime heap implicitly: Rust validation and examples should back `GlobalAlloc` with the `malloc`/`free`/`realloc` family from `libcrt.a`, relying on the C runtime to honour `__heap_implementation`. No Rust-side pluggable allocator framework is part of milestone 2.

## Implementation Changes

### 1. Builder and payload profiles

Refactor the repo to support two explicit payload profiles:

- `core`
  - builds `core` + `compiler_builtins`
  - preserves the current milestone 1 behaviour
- `alloc`
  - builds `core` + `alloc` + `compiler_builtins`
  - is the new default release payload for downstream consumers

Make the builder interface decision-complete and stable:

- introduce a shared builder entry point, for example `scripts/build-payload.sh --profile core|alloc`
- keep `scripts/build-core.sh` as a thin compatibility wrapper over `--profile core`
- add `scripts/build-alloc.sh` as a thin wrapper over `--profile alloc`

Do the same for validation:

- introduce a shared validator, for example `scripts/validate-payload.sh --profile core|alloc`
- keep `scripts/validate-link.sh` as the `core` wrapper
- add `scripts/validate-alloc.sh` as the `alloc` wrapper

Profile behaviour:

- `core` uses `-Z build-std=core,compiler_builtins`
- `alloc` uses `-Z build-std=core,alloc,compiler_builtins`

Payload contents:

- `core` profile ships `libcore` and `libcompiler_builtins`
- `alloc` profile additionally ships `liballoc`
- both profiles continue to ship the same `rustlib/aarch64-unknown-none/lib/` subtree layout

Manifest changes:

- add `profile=core|alloc`
- keep `includes_core=yes`
- keep `includes_compiler_builtins=yes`
- set `includes_alloc=yes|no`

### 2. Validation crates and allocator behaviour

Keep validation crate-specific; do not add a general-purpose allocator crate to the payload.

Add an `alloc` smoke-validation crate that proves the shipped `alloc` works in a `no_std` binary linked through `riscos64-link`. The validation crate must include:

- `#![no_std]`
- `#![no_main]`
- `#[panic_handler]`
- an allocation-failure handler if required by the toolchain for `no_std + alloc`
- a `#[global_allocator]`

The `#[global_allocator]` implementation should:

- call C runtime `malloc`, `free`, and `realloc` for ordinary layouts
- rely on that path to inherit the current `__heap_implementation` selection
- include a correct fallback for over-aligned layouts rather than assuming `malloc` is always sufficient
- treat this as validation/example support code only, not as a shipped target library

The alloc smoke test should exercise real `alloc` functionality, at minimum:

- `Box`
- `Vec` growth and reallocation
- `String` creation and append
- one path that proves a reallocation happens rather than only fixed-size allocation

The binary should print a simple success string and exit cleanly via the existing CRT model.

### 3. Release and CI behaviour

Keep one repo and one workflow, but make both profiles first-class CI targets.

On pushes and pull requests:

- build both `core` and `alloc` payloads
- run both validation flows
- upload both archives as workflow artifacts

On tagged releases:

- publish two archives
- make the alloc-inclusive payload the primary downstream artifact:
  - `RISCOS64-RustCore-<version>.zip`
- publish the core-only compatibility artifact separately:
  - `RISCOS64-RustCore-coreonly-<version>.zip`

This preserves a clean default for the build environment while keeping the milestone 1 payload available for comparison and debugging.

## Downstream build-environment changes

After the new release exists, update `/riscos-source` to consume the alloc-inclusive archive as the default Rust payload.

Required downstream changes:

- update the fetched release URL/version in `crosscompile/Makefile`
- continue unpacking into the same Rust toolchain location in `crosscompile/Dockerfile.64bit`
- extend `crosscompile/tests/test-install.sh` with an `alloc` smoke test using stable Cargo
- keep `crosscompile/rust/cargo-config.toml` minimal: target, linker, archiver only

The downstream `alloc` install test should:

- build a `no_std` Rust crate with `cargo rustc --target aarch64-unknown-none -- --emit=obj=...`
- define its own `#[global_allocator]` backed by the C runtime
- use `Vec` and `String`
- link with `riscos64-link -aif`
- run under `riscos-build-run --64`
- assert expected output

Documentation updates:

- extend `crosscompile/help/howto-rust.md` with an `alloc` section
- state clearly that `alloc` is available offline, but user crates must still define `#[global_allocator]`
- include a minimal allocator example and mention that it inherits the active C heap implementation

## CI inspection enablement for agents

Because `gh` is already installed in the environment, enable direct CI inspection through local GitHub CLI auth rather than inventing a separate transport.

Plan this as a small repo-adjacent support task:

- document in `riscos64-rust-core/AGENTS.md` that agents may use `gh run list`, `gh run view --log-failed`, and `gh release view` once authenticated
- recommend one-time local `gh` authentication in the environment or a configured `GH_TOKEN`
- optionally add a tiny helper such as `scripts/ci-status.sh` that wraps:
  - recent workflow runs for `build.yml`
  - failed-job log access
  - current release artifact visibility

This is not a blocker for milestone 2 payload work, but it should be done alongside it so future sessions do not depend on relayed CI logs.

## Test Plan

Repository-level:

- `core` profile still builds and validates exactly as before
- `alloc` profile builds successfully with upstream `alloc`
- both payload manifests report the correct included-library flags
- both release archives are produced with the correct names

Alloc validation:

- `Box`, `Vec`, and `String` compile and link in a `no_std` AIF
- reallocation works
- the binary runs successfully via `riscos-build-run --64`
- panic and allocation-failure paths both terminate cleanly through the CRT model

Downstream integration:

- stable Cargo in the built image can build an `alloc`-using 64-bit Rust crate offline
- the crate links through `riscos64-link`
- the resulting AIF runs successfully
- existing `core`-only Rust flow does not regress

## Assumptions and defaults

- `alloc` stays in the same repository as milestone 2, not a new repo.
- The existing `aarch64-unknown-none` target remains the basis for milestone 2.
- The C runtime `malloc` family remains the allocator backend and continues to honour `__heap_implementation`.
- No Rust-side pluggable allocator framework is introduced in milestone 2.
- No `std` work is included.
- No shared Cargo config changes are made beyond the current target/linker/archiver settings.
- The payload does not ship a reusable allocator crate; user binaries continue to define `#[global_allocator]` themselves.
