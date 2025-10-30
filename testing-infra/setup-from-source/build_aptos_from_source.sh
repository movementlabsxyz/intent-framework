#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
AP_DIR="$ROOT_DIR/infra/external/aptos-core"
LOCK_FILE="$ROOT_DIR/infra/external/aptos-core.lock"
VERIFY_SCRIPT="$ROOT_DIR/infra/external/verify-aptos-pin.sh"
SETUP_SCRIPT="$ROOT_DIR/move-intent-framework/tests/cross_chain/setup_aptos_core.sh"

echo "[build] Building Aptos from Movement's aptos-core fork..."
echo "[build] repo: $ROOT_DIR"
echo "[build] aptos-core dir: $AP_DIR"

echo "[build] Ensuring Movement aptos-core is present (l1-migration)…"
bash "$SETUP_SCRIPT"

if [ ! -f "$LOCK_FILE" ] || [ "$(tr -d ' \t\n' < "$LOCK_FILE")" = "0000000000000000000000000000000000000000" ]; then
  echo "[build] Updating lock file with current HEAD for reproducibility." >&2
  git -C "$AP_DIR" rev-parse HEAD > "$LOCK_FILE"
fi

echo "[build] Verifying aptos-core pin…"
bash "$VERIFY_SCRIPT"

echo "[build] Building aptos CLI (release)…"
APTOS_CLI_BIN="$AP_DIR/target/release/aptos"
if [ ! -f "$APTOS_CLI_BIN" ] || [ "$(stat -f %m "$APTOS_CLI_BIN" 2>/dev/null || echo 0)" -lt "$(stat -f %m "$AP_DIR/Cargo.toml" 2>/dev/null || echo 0)" ]; then
  pushd "$AP_DIR" >/dev/null
  cargo build -p aptos --release
  popd >/dev/null
else
  echo "[build] aptos CLI binary already built and up-to-date."
fi

echo "[build] Building aptos-node (release)…"
APTOS_NODE_BIN="$AP_DIR/target/release/aptos-node"
if [ ! -f "$APTOS_NODE_BIN" ] || [ "$(stat -f %m "$APTOS_NODE_BIN" 2>/dev/null || echo 0)" -lt "$(stat -f %m "$AP_DIR/Cargo.toml" 2>/dev/null || echo 0)" ]; then
  pushd "$AP_DIR" >/dev/null
  cargo build -p aptos-node --release
  popd >/dev/null
else
  echo "[build] aptos-node binary already built and up-to-date."
fi

echo "[build] Building aptos-faucet-service (release)…"
APTOS_FAUCET_BIN="$AP_DIR/target/release/aptos-faucet-service"
if [ ! -f "$APTOS_FAUCET_BIN" ] || [ "$(stat -f %m "$APTOS_FAUCET_BIN" 2>/dev/null || echo 0)" -lt "$(stat -f %m "$AP_DIR/Cargo.toml" 2>/dev/null || echo 0)" ]; then
  pushd "$AP_DIR" >/dev/null
  cargo build -p aptos-faucet-service --release
  popd >/dev/null
else
  echo "[build] aptos-faucet-service binary already built and up-to-date."
fi

echo "[build] ✅ Build complete!"
echo "[build] Binaries available at:"
echo "[build]   - $APTOS_CLI_BIN"
echo "[build]   - $APTOS_NODE_BIN"
echo "[build]   - $APTOS_FAUCET_BIN"
echo "[build]"
echo "[build] Now you can run:"
echo "[build]   - ./infra/setup-from-source/setup-chain-a.sh"
echo "[build]   - ./infra/setup-from-source/setup-chain-b.sh"