#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${RUST_TOOLCHAIN:-nightly-2026-06-08}"
TARGET="${RUST_TARGET:-aarch64-unknown-none}"
RUSTUP_HOME="${RUSTUP_HOME:-$ROOT_DIR/.local-rustup}"
CARGO_HOME="${CARGO_HOME:-$ROOT_DIR/.local-cargo}"
TARGET_DIR="${TARGET_DIR:-$ROOT_DIR/build/target}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$ROOT_DIR/build/payload}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/build/dist}"
MANIFEST_PATH="$PAYLOAD_DIR/manifest.txt"
LIB_DIR="$PAYLOAD_DIR/rustlib/$TARGET/lib"

rustup_cmd() {
    env -u CARGO_HOME RUSTUP_HOME="$RUSTUP_HOME" rustup "$@"
}

mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" "$TARGET_DIR" "$LIB_DIR" "$DIST_DIR"

rustup_cmd toolchain install "$TOOLCHAIN" --profile minimal
rustup_cmd component add rust-src --toolchain "$TOOLCHAIN"
rustup_cmd target add "$TARGET" --toolchain "$TOOLCHAIN"
CARGO_BIN="$(rustup_cmd which cargo --toolchain "$TOOLCHAIN")"

env RUSTUP_HOME="$RUSTUP_HOME" CARGO_HOME="$CARGO_HOME" "$CARGO_BIN" build \
    -Z build-std=core,compiler_builtins \
    --manifest-path "$ROOT_DIR/smoke-build/Cargo.toml" \
    --target "$TARGET" \
    --release \
    --target-dir "$TARGET_DIR"

rm -rf "$LIB_DIR"
mkdir -p "$LIB_DIR"

find "$TARGET_DIR/$TARGET/release/deps" -maxdepth 1 -type f \
    \( -name 'libcore-*.rlib' -o -name 'libcore-*.rmeta' \
       -o -name 'libcompiler_builtins-*.rlib' -o -name 'libcompiler_builtins-*.rmeta' \) \
    -exec cp {} "$LIB_DIR/" \;

RUSTC_VERSION="$(rustup_cmd run "$TOOLCHAIN" rustc --version)"
cat > "$MANIFEST_PATH" <<EOF
artifact=riscos64-rust-core
toolchain=$TOOLCHAIN
rustc=$RUSTC_VERSION
target=$TARGET
includes_core=yes
includes_compiler_builtins=yes
includes_alloc=no
EOF

(
    cd "$PAYLOAD_DIR"
    zip -qr "$DIST_DIR/riscos64-rust-core-$TOOLCHAIN-$TARGET.zip" .
)

echo "Payload prepared in $PAYLOAD_DIR"
echo "Zip artifact: $DIST_DIR/riscos64-rust-core-$TOOLCHAIN-$TARGET.zip"
