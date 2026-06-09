#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${RUST_TOOLCHAIN:-nightly-2026-06-08}"
TARGET="${RUST_TARGET:-aarch64-unknown-none}"
RUSTUP_HOME="${RUSTUP_HOME:-$ROOT_DIR/.local-rustup}"
CARGO_HOME="${CARGO_HOME:-$ROOT_DIR/.local-cargo}"
WORK_ROOT="$ROOT_DIR/build/validate"
TARGET_DIR="$ROOT_DIR/build/validate-target"
LOCAL_RUSTUP="$CARGO_HOME/bin/rustup"
LOCAL_CARGO="$CARGO_HOME/bin/cargo"

PROFILE=""

usage() {
    echo "Usage: $0 --profile core|alloc" >&2
    exit 1
}

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

find_library() {
    local pattern="$1"
    find "$PAYLOAD_LIB_DIR" -maxdepth 1 -type f -name "$pattern" | head -n 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile)
            [ "$#" -ge 2 ] || usage
            PROFILE="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

case "$PROFILE" in
    core)
        BUILD_STD="core,compiler_builtins"
        CRATE_MANIFEST="$ROOT_DIR/smoke-link/Cargo.toml"
        OUTPUT_BASENAME="hello"
        ;;
    alloc)
        BUILD_STD="core,alloc,compiler_builtins"
        CRATE_MANIFEST="$ROOT_DIR/smoke-alloc/Cargo.toml"
        OUTPUT_BASENAME="alloc-smoke"
        ;;
    *)
        usage
        ;;
esac

PAYLOAD_LIB_DIR="$ROOT_DIR/build/payload/$PROFILE/rustlib/$TARGET/lib"
WORK_DIR="$WORK_ROOT/$PROFILE"
OBJECT_PATH="$WORK_DIR/$OUTPUT_BASENAME.o"
AIF_PATH="$WORK_DIR/$OUTPUT_BASENAME,ff8"

mkdir -p "$WORK_DIR" "$TARGET_DIR"
bootstrap_rustup

if [ ! -d "$PAYLOAD_LIB_DIR" ]; then
    echo "Payload libraries not found in $PAYLOAD_LIB_DIR" >&2
    echo "Run ./scripts/build-payload.sh --profile $PROFILE first." >&2
    exit 1
fi

rustup_cmd toolchain install "$TOOLCHAIN" --profile minimal
rustup_cmd component add rust-src --toolchain "$TOOLCHAIN"
rustup_cmd target add "$TARGET" --toolchain "$TOOLCHAIN"

env RUSTUP_HOME="$RUSTUP_HOME" CARGO_HOME="$CARGO_HOME" \
    "$LOCAL_CARGO" +"$TOOLCHAIN" rustc \
    -Z build-std="$BUILD_STD" \
    --manifest-path "$CRATE_MANIFEST" \
    --target "$TARGET" \
    --release \
    --target-dir "$TARGET_DIR" \
    -- \
    --emit=obj="$OBJECT_PATH"

CORE_RLIB="$(find_library 'libcore-*.rlib')"
COMPILER_BUILTINS_RLIB="$(find_library 'libcompiler_builtins-*.rlib')"

if [ -z "$CORE_RLIB" ] || [ -z "$COMPILER_BUILTINS_RLIB" ]; then
    echo "Could not locate packaged Rust libraries in $PAYLOAD_LIB_DIR" >&2
    exit 1
fi

LINK_INPUTS=("$OBJECT_PATH")

if [ "$PROFILE" = "alloc" ]; then
    ALLOC_RLIB="$(find_library 'liballoc-*.rlib')"
    if [ -z "$ALLOC_RLIB" ]; then
        echo "Could not locate packaged alloc library in $PAYLOAD_LIB_DIR" >&2
        exit 1
    fi
    LINK_INPUTS+=("$ALLOC_RLIB")
fi

LINK_INPUTS+=(
    "$CORE_RLIB"
    "$COMPILER_BUILTINS_RLIB"
)

riscos64-link -aif -o "$AIF_PATH" "${LINK_INPUTS[@]}"

riscos-build-run --64 "$AIF_PATH" --command "Run $OUTPUT_BASENAME"
