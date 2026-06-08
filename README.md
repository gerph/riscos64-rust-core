# riscos64-rust-core

This repository builds a packaged Rust target-library payload for RISC OS 64-bit
work based on the upstream `aarch64-unknown-none` target.

Milestone 1 focuses on `core` and `compiler_builtins`. It does not include
`alloc`, `std`, or any RISC OS-specific Rust OS bindings.

## What this repo produces

The build creates a zip file containing:

- a deterministic `rustlib/aarch64-unknown-none/lib/` subtree
- the `libcore` and `libcompiler_builtins` artifacts built from source
- a simple manifest describing the toolchain and target used

The payload is intended to be installed into the Rust toolchain tree used in the
RISC OS build environment.

GitHub Actions renames the built archive to `RISCOS64-RustCore-<version>.zip`.
Tag builds for tags beginning with `v` also create a draft GitHub release with
that archive attached.

## Builder model

The repo uses a repo-local Rustup installation and nightly toolchain for
building upstream Rust libraries from source. The shared user toolchain does not
need to be changed.

The builder uses:

- nightly Cargo
- `rust-src`
- `-Z build-std=core,compiler_builtins`

The scripts bootstrap their own Rustup installation under `.local-cargo/` and
`.local-rustup/`.

The builder also needs a host C toolchain on the Linux side because
`compiler_builtins` uses a host build script. In this environment that meant
installing `build-essential`.

## Quick start

Build and package the payload:

```sh
./scripts/build-core.sh
```

Validate that the produced libraries can link a direct Rust object into an AIF:

```sh
./scripts/validate-link.sh
```

The validation script intentionally compiles the test object with the same
`build-std` flow as the packaged payload. A raw `rustc` compile against the
toolchain sysroot can produce mismatched `core` symbol hashes.

## Output

The build products are written under `build/`:

- `build/payload/` unpacked payload tree
- `build/dist/` zip release artifacts
- `build/target/` Cargo build output
- `build/validate/` link validation outputs
