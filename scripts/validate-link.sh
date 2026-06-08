#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${RUST_TOOLCHAIN:-nightly-2026-06-08}"
TARGET="${RUST_TARGET:-aarch64-unknown-none}"
RUSTUP_HOME="${RUSTUP_HOME:-$ROOT_DIR/.local-rustup}"
CARGO_HOME="${CARGO_HOME:-$ROOT_DIR/.local-cargo}"
WORK_DIR="$ROOT_DIR/build/validate"
TARGET_DIR="$ROOT_DIR/build/validate-target"
PAYLOAD_LIB_DIR="$ROOT_DIR/build/payload/rustlib/$TARGET/lib"
LOCAL_RUSTUP="$CARGO_HOME/bin/rustup"
LOCAL_CARGO="$CARGO_HOME/bin/cargo"

bootstrap_rustup() {
    mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"

    if [ -x "$LOCAL_RUSTUP" ]; then
        return
    fi

    if command -v curl >/dev/null 2>&1; then
        env CARGO_HOME="$CARGO_HOME" RUSTUP_HOME="$RUSTUP_HOME" \
            sh -c 'curl https://sh.rustup.rs -sSf | \
                   sh -s -- -y --no-modify-path \
                              --default-toolchain none \
                              --profile minimal'
    elif command -v wget >/dev/null 2>&1; then
        env CARGO_HOME="$CARGO_HOME" RUSTUP_HOME="$RUSTUP_HOME" \
            sh -c 'wget -qO- https://sh.rustup.rs | \
                   sh -s -- -y --no-modify-path \
                              --default-toolchain none \
                              --profile minimal'
    else
        echo "Neither curl nor wget is available to bootstrap rustup." >&2
        exit 1
    fi
}

rustup_cmd() {
    env CARGO_HOME="$CARGO_HOME" RUSTUP_HOME="$RUSTUP_HOME" \
        "$LOCAL_RUSTUP" "$@"
}

mkdir -p "$WORK_DIR" "$TARGET_DIR"
bootstrap_rustup

if [ ! -d "$PAYLOAD_LIB_DIR" ]; then
    echo "Payload libraries not found in $PAYLOAD_LIB_DIR" >&2
    echo "Run ./scripts/build-core.sh first." >&2
    exit 1
fi

rustup_cmd toolchain install "$TOOLCHAIN" --profile minimal
rustup_cmd component add rust-src --toolchain "$TOOLCHAIN"
rustup_cmd target add "$TARGET" --toolchain "$TOOLCHAIN"

env RUSTUP_HOME="$RUSTUP_HOME" CARGO_HOME="$CARGO_HOME" \
    "$LOCAL_CARGO" +"$TOOLCHAIN" rustc \
    -Z build-std=core,compiler_builtins \
    --manifest-path "$ROOT_DIR/smoke-link/Cargo.toml" \
    --target "$TARGET" \
    --release \
    --target-dir "$TARGET_DIR" \
    -- \
    --emit=obj="$WORK_DIR/hello.o"

CORE_RLIB="$(find "$PAYLOAD_LIB_DIR" -maxdepth 1 -type f -name 'libcore-*.rlib' | head -n 1)"
COMPILER_BUILTINS_RLIB="$(find "$PAYLOAD_LIB_DIR" -maxdepth 1 -type f -name 'libcompiler_builtins-*.rlib' | head -n 1)"

if [ -z "$CORE_RLIB" ] || [ -z "$COMPILER_BUILTINS_RLIB" ]; then
    echo "Could not locate packaged Rust libraries in $PAYLOAD_LIB_DIR" >&2
    exit 1
fi

riscos64-link \
    -aif \
    -o "$WORK_DIR/hello,ff8" \
    "$WORK_DIR/hello.o" \
    "$CORE_RLIB" \
    "$COMPILER_BUILTINS_RLIB"

riscos-build-run --64 "$WORK_DIR/hello,ff8" --command 'Run hello'
