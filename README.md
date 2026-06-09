# riscos64-rust-core

This repository builds packaged Rust target-library payloads for RISC OS 64-bit
work based on the upstream `aarch64-unknown-none` target.

Milestone 2 adds upstream `alloc` while keeping the milestone 1 `core`-only
payload available as a compatibility profile. It still does not include `std`
or any RISC OS-specific Rust OS bindings.

## What this repo produces

Each build profile creates a zip file containing:

- a deterministic `rustlib/aarch64-unknown-none/lib/` subtree
- the `libcore` and `libcompiler_builtins` artifacts built from source
- the `alloc` profile also includes `liballoc`
- a simple manifest describing the toolchain and target used

The payload is intended to be installed into the Rust toolchain tree used in the
RISC OS build environment.

GitHub Actions publishes both profiles. Tagged releases attach:

- `RISCOS64-RustCore-<version>.zip` for the alloc-inclusive default payload
- `RISCOS64-RustCore-coreonly-<version>.zip` for the core-only compatibility payload

## Builder model

The repo uses a repo-local Rustup installation and nightly toolchain for
building upstream Rust libraries from source. The shared user toolchain does not
need to be changed.

The builder uses:

- nightly Cargo
- `rust-src`
- `-Z build-std=core,compiler_builtins` for the `core` profile
- `-Z build-std=core,alloc,compiler_builtins` for the `alloc` profile

The scripts bootstrap their own Rustup installation under `.local-cargo/` and
`.local-rustup/`.

The builder also needs a host C toolchain on the Linux side because
`compiler_builtins` uses a host build script. In this environment that meant
installing `build-essential`.

## Quick start

Build and package the alloc-inclusive payload:

```sh
./scripts/build-alloc.sh
```

Build the core-only compatibility payload:

```sh
./scripts/build-core.sh
```

Validate the alloc-inclusive payload:

```sh
./scripts/validate-alloc.sh
```

Validate that the core-only payload can still link a direct Rust object into an
AIF:

```sh
./scripts/validate-link.sh
```

The validation script intentionally compiles the test object with the same
`build-std` flow as the packaged payload. A raw `rustc` compile against the
toolchain sysroot can produce mismatched `core` symbol hashes.

## Output

The build products are written under `build/`:

- `build/payload/core/` unpacked core-only payload tree
- `build/payload/alloc/` unpacked alloc-inclusive payload tree
- `build/dist/` zip release artifacts
- `build/target/` Cargo build output
- `build/validate/` per-profile validation outputs
