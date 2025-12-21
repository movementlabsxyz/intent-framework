#!/bin/bash

# Configure Verifier for Connected EVM Chain
# 
# This script adds the [connected_chain_evm] section to verifier-e2e-ci-testing.toml.
# Must be called AFTER chain-hub/configure-verifier.sh which creates the base config.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-connected-evm"
cd "$PROJECT_ROOT"

log_and_echo "✅ Configuring verifier for Connected EVM Chain..."
log_and_echo ""

# Get EVM escrow contract address (single contract, one escrow per intentId)
CONTRACT_ADDRESS=$(extract_escrow_contract_address)
log_and_echo "   EVM Escrow Contract: $CONTRACT_ADDRESS"

# Get verifier Ethereum address (Hardhat account 0)
log "   - Getting verifier Ethereum address (Hardhat account 0)..."
VERIFIER_ADDRESS=$(get_hardhat_account_address "0")
log_and_echo "   EVM Verifier: $VERIFIER_ADDRESS"

# Config file path (created by chain-hub/configure-verifier.sh)
VERIFIER_E2E_CI_TESTING_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier-e2e-ci-testing.toml"

if [ ! -f "$VERIFIER_E2E_CI_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: Config file not found. Run chain-hub/configure-verifier.sh first."
    exit 1
fi

# Append connected_chain_evm section to config (insert before [verifier] section)
# First, create a temp file with the new section
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << EOF

[connected_chain_evm]
name = "Connected EVM Chain"
rpc_url = "http://127.0.0.1:8545"
escrow_contract_addr = "$CONTRACT_ADDRESS"
chain_id = 31337
verifier_addr = "$VERIFIER_ADDRESS"
EOF

# Insert the EVM section before [verifier] section
awk -v evm_section="$(cat $TEMP_FILE)" '
/^\[verifier\]/ { print evm_section; print ""; }
{ print }
' "$VERIFIER_E2E_CI_TESTING_CONFIG" > "${VERIFIER_E2E_CI_TESTING_CONFIG}.tmp"
mv "${VERIFIER_E2E_CI_TESTING_CONFIG}.tmp" "$VERIFIER_E2E_CI_TESTING_CONFIG"

rm -f "$TEMP_FILE"

export VERIFIER_CONFIG_PATH="$VERIFIER_E2E_CI_TESTING_CONFIG"

log_and_echo "✅ Added Connected EVM Chain section to verifier config"
log_and_echo ""

