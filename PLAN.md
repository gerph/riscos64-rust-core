# Plan: Introduce riscos64-rust-core and import it into the build environment

## Summary

Build and ship upstream Rust `core` as a dedicated companion project,
`riscos64-rust-core`, then consume its release artifact from the build
environment so 64-bit Rust builds can use prebuilt Rust target libraries
without network fetches.

Milestone 1 will deliver `core` only, not `alloc`. The build path will use a
nightly builder with `rust-src`, but the user-facing environment will remain
primarily stable. The initial target will stay on `aarch64-unknown-none`; a
custom RISC OS Rust target is deferred unless `core` build or link failures
prove it necessary.

## Key Changes

### 1. New companion repo: `riscos64-rust-core`

Create a standalone build repo responsible for producing a versioned zip release
containing the prebuilt Rust target libraries for `aarch64-unknown-none`.

The repo builds upstream Rust libraries from source using nightly Cargo with
`-Z build-std=core` and `rust-src`.

The build output is an offline target payload, not a crates.io mirror and not a
source bundle.

The first release exports the minimum target sysroot content needed for
`no_std` linking:

- `libcore`
- `libcompiler_builtins`
- any target-side metadata files required by `rustc` for that target directory

`alloc` is explicitly excluded from milestone 1, but the repo layout must
reserve a straightforward path for later adding it without changing the artifact
format.

### 2. Artifact format and release contract

Publish a versioned zip release from `riscos64-rust-core`, following the same
release-asset model already used for other 64-bit runtime payloads in this
environment.

The zip should unpack into a deterministic target-sysroot subtree suitable for
direct installation under the Rust toolchain tree used in the image.

Default contract:

- target: `aarch64-unknown-none`
- channel used to build: nightly, pinned in the companion repo
- shipped libraries are prebuilt artifacts only
- no automatic network access is required by downstream users after the image is
  built

Include a small manifest file in the zip with:

- companion repo version
- Rust nightly version used
- target triple
- whether `core` and `compiler_builtins` are included
- whether `alloc` is included

Do not include the OS-level Rust interface library in this milestone.

### 3. Build-environment integration in this repo

Extend `crosscompile/Makefile` to fetch the `riscos64-rust-core` release zip
into `crosscompile/work`, following the same pattern used for `riscos64-clib`
and `riscos64-c++lib`.

Extend `crosscompile/Dockerfile.64bit` to unpack the Rust core payload into the
installed Rust toolchain/sysroot area alongside the existing
`aarch64-unknown-none` target files.

Keep `crosscompile/rust/cargo-config.toml` minimal:

- keep target, linker, and archiver
- do not add panic/codegen policy flags globally
- do not force nightly in the user config

Add user-facing help documenting that:

- the environment includes prebuilt Rust target libraries for 64-bit `no_std`
- stable remains the default user toolchain
- nightly is only required for rebuilding the shipped Rust core payload, not for
  ordinary use of the environment once the payload is installed

### 4. Runtime and linking model

Continue using the existing C runtime model:

- `libcrt.a` provides startup and exit
- Rust binaries provide `main`
- Rust panic handlers remain crate-defined for `no_std`

Treat Rust support as layered on top of the existing `riscos64-clib` contract,
not as a replacement runtime.

The milestone must prove that normal checked `core` paths link cleanly without
project-local workarounds such as disabling debug assertions or overflow checks
in order to avoid unresolved `core::panicking` references.

If upstream `core` on `aarch64-unknown-none` still leaves unresolved
target/runtime expectations after `build-std=core`, document those precisely
and assign them either to:

- companion repo build configuration
- Rust target definition gap
- `riscos64-clib` missing support surface

## Implementation Notes

Use nightly only in the companion-repo build path or builder context; do not
convert the whole interactive environment to nightly-by-default.

Pin the nightly version in `riscos64-rust-core` so releases are reproducible.

Prefer a staged validation path in the companion repo:

1. build `core`
2. inspect produced target libs
3. link a tiny `no_std` test object against the shipped payload plus `libcrt.a`
4. run the resulting AIF under `riscos-build-run --64`

Keep the first target triple as `aarch64-unknown-none`. Only introduce a custom
target JSON if one of these becomes true:

- wrong ABI assumptions
- wrong relocation/code model assumptions
- `core` cannot be built or linked cleanly with the existing triple
- the shipped libraries need target options not expressible through current
  flags

## Test Plan

- Companion repo build test:
  - nightly + `rust-src` can build `core` for `aarch64-unknown-none`
  - release zip is produced with the expected manifest and target subtree
- Build-environment integration test:
  - image build installs the payload into the Rust toolchain tree
  - `/user/.cargo/config.toml` remains limited to target/linker/ar settings
- Functional Rust tests in this environment:
  - a minimal `no_std` Hello World AIF links and runs
  - a binary using checked indexing or other ordinary `core` code paths links
    without unresolved `core::panicking` symbols
  - a crate with a panic handler still links through `libcrt.a`
- Offline expectation:
  - a user can build a 64-bit `no_std` Rust binary in the image without
    downloading Rust target libraries during the build

## Assumptions and Defaults

- Milestone 1 ships `core` only; `alloc` is planned later.
- The payload is delivered as a versioned zip release asset, not as
  repo-local-only staging.
- The build-environment changes are part of the same end-to-end milestone.
- The OS-level Rust interface library is explicitly out of scope for this
  milestone.
- Global Cargo config will not be expanded with project-specific codegen or
  panic policy; those remain per-project decisions.
- The existing `aarch64-unknown-none` target is the starting point, with a
  custom RISC OS Rust target deferred until justified by concrete failures.
