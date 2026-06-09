#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${RUST_TOOLCHAIN:-nightly-2026-06-08}"
TARGET="${RUST_TARGET:-aarch64-unknown-none}"
RUSTUP_HOME="${RUSTUP_HOME:-$ROOT_DIR/.local-rustup}"
CARGO_HOME="${CARGO_HOME:-$ROOT_DIR/.local-cargo}"
TARGET_DIR="${TARGET_DIR:-$ROOT_DIR/build/target}"
PAYLOAD_ROOT="${PAYLOAD_ROOT:-$ROOT_DIR/build/payload}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/build/dist}"
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
        INCLUDES_ALLOC="no"
        ;;
    alloc)
        BUILD_STD="core,alloc,compiler_builtins"
        INCLUDES_ALLOC="yes"
        ;;
    *)
        usage
        ;;
esac

PAYLOAD_DIR="$PAYLOAD_ROOT/$PROFILE"
MANIFEST_PATH="$PAYLOAD_DIR/manifest.txt"
LIB_DIR="$PAYLOAD_DIR/rustlib/$TARGET/lib"
ARCHIVE_PATH="$DIST_DIR/riscos64-rust-core-$PROFILE-$TOOLCHAIN-$TARGET.zip"

mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" "$TARGET_DIR" "$LIB_DIR" "$DIST_DIR"
bootstrap_rustup

rustup_cmd toolchain install "$TOOLCHAIN" --profile minimal
rustup_cmd component add rust-src --toolchain "$TOOLCHAIN"
rustup_cmd target add "$TARGET" --toolchain "$TOOLCHAIN"

env RUSTUP_HOME="$RUSTUP_HOME" CARGO_HOME="$CARGO_HOME" \
    "$LOCAL_CARGO" +"$TOOLCHAIN" build \
    -Z build-std="$BUILD_STD" \
    --manifest-path "$ROOT_DIR/smoke-build/Cargo.toml" \
    --target "$TARGET" \
    --release \
    --target-dir "$TARGET_DIR"

rm -rf "$LIB_DIR"
mkdir -p "$LIB_DIR"

find "$TARGET_DIR/$TARGET/release/deps" -maxdepth 1 -type f \
    \( -name 'libcore-*.rlib' -o -name 'libcore-*.rmeta' \
       -o -name 'libcompiler_builtins-*.rlib' -o -name 'libcompiler_builtins-*.rmeta' \
       -o -name 'liballoc-*.rlib' -o -name 'liballoc-*.rmeta' \) \
    -exec cp {} "$LIB_DIR/" \;

if [ "$INCLUDES_ALLOC" = "no" ]; then
    find "$LIB_DIR" -maxdepth 1 -type f \
        \( -name 'liballoc-*.rlib' -o -name 'liballoc-*.rmeta' \) \
        -delete
fi

RUSTC_VERSION="$(rustup_cmd run "$TOOLCHAIN" rustc --version)"
cat > "$MANIFEST_PATH" <<EOF
artifact=riscos64-rust-core
profile=$PROFILE
toolchain=$TOOLCHAIN
rustc=$RUSTC_VERSION
target=$TARGET
includes_core=yes
includes_compiler_builtins=yes
includes_alloc=$INCLUDES_ALLOC
EOF

rm -f "$ARCHIVE_PATH"
(
    cd "$PAYLOAD_DIR"
    zip -qr "$ARCHIVE_PATH" .
)

echo "Payload prepared in $PAYLOAD_DIR"
echo "Zip artifact: $ARCHIVE_PATH"
