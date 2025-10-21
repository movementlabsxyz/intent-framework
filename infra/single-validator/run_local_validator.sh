#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
AP_DIR="$ROOT_DIR/infra/external/aptos-core"
LOCK_FILE="$ROOT_DIR/infra/external/aptos-core.lock"
VERIFY_SCRIPT="$ROOT_DIR/infra/external/verify-aptos-pin.sh"
SETUP_SCRIPT="$ROOT_DIR/move-intent-framework/tests/cross_chain/setup_aptos_core.sh"

# Allow override, but default under repo
NODE_HOME_DEFAULT="$ROOT_DIR/infra/single-validator/work"
NODE_HOME="${NODE_HOME:-$NODE_HOME_DEFAULT}"

echo "[run] repo: $ROOT_DIR"
echo "[run] aptos-core dir: $AP_DIR"
echo "[run] node home: $NODE_HOME"

mkdir -p "$NODE_HOME/data"

echo "[run] Ensuring Movement aptos-core is present (l1-migration)…"
bash "$SETUP_SCRIPT"

if [ ! -f "$LOCK_FILE" ] || [ "$(tr -d ' \t\n' < "$LOCK_FILE")" = "0000000000000000000000000000000000000000" ]; then
  echo "[run] Updating lock file with current HEAD for reproducibility." >&2
  git -C "$AP_DIR" rev-parse HEAD > "$LOCK_FILE"
fi

echo "[run] Verifying aptos-core pin…"
bash "$VERIFY_SCRIPT"

echo "[run] Building aptos-node (release)…"
APTOS_NODE_BIN="$AP_DIR/target/release/aptos-node"
if [ ! -f "$APTOS_NODE_BIN" ] || [ "$(stat -f %m "$APTOS_NODE_BIN" 2>/dev/null || echo 0)" -lt "$(stat -f %m "$AP_DIR/Cargo.toml" 2>/dev/null || echo 0)" ]; then
  pushd "$AP_DIR" >/dev/null
  cargo build -p aptos-node --release
  popd >/dev/null
else
  echo "[run] aptos-node binary already built and up-to-date."
fi

VAL_IDENTITY="$NODE_HOME/validator-identity.yaml"
if [ ! -f "$VAL_IDENTITY" ]; then
  echo "[run] ERROR: validator identity not found at $VAL_IDENTITY" >&2
  echo "       Place your validator-identity.yaml there, then re-run." >&2
  exit 1
fi

echo "[run] Configuring validator via Aptos CLI…"
aptos genesis set-validator-configuration \
  --local-repository-dir "$NODE_HOME/data" \
  --username mvt_val \
  --owner-public-identity-file "$VAL_IDENTITY" \
  --validator-host 0.0.0.0:6180

echo "[run] Generating layout template…"
aptos genesis generate-layout-template \
  --output-file "$NODE_HOME/data/layout.yaml" \
  --assume-yes

echo "[run] Setting root key in layout…"
ROOT_KEY=$(grep account_public_key "$VAL_IDENTITY" | cut -d'"' -f2)
sed -i.bak "s/root_key: ~/root_key: \"$ROOT_KEY\"/" "$NODE_HOME/data/layout.yaml"

echo "[run] Downloading genesis files from Aptos testnet…"
cd "$NODE_HOME/data"
curl -s -O https://raw.githubusercontent.com/aptos-labs/aptos-networks/main/testnet/genesis.blob
curl -s -O https://raw.githubusercontent.com/aptos-labs/aptos-networks/main/testnet/waypoint.txt
cd - >/dev/null

CFG_SRC="$ROOT_DIR/infra/single-validator/validator_node.yaml"
CFG_DST="$NODE_HOME/validator_node.yaml"
cp "$CFG_SRC" "$CFG_DST"
sed -i.bak "s#UPDATE_TO_YOUR_PATH#$NODE_HOME#g" "$CFG_DST"

echo "[run] Starting validator…"
"$AP_DIR/target/release/aptos-node" -f "$CFG_DST" &
NODE_PID=$!
echo "[run] aptos-node PID: $NODE_PID"

echo "[run] Waiting for REST API…"
for i in {1..20}; do
  if curl -sSf http://127.0.0.1:8080/v1 >/dev/null 2>&1; then
    echo "[run] REST ready at http://127.0.0.1:8080/v1"
    exit 0
  fi
  sleep 1
done

echo "[run] WARN: REST not responding yet; node is running (PID $NODE_PID)." >&2
exit 1


