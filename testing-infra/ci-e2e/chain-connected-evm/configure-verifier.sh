#!/bin/bash

# Configure Verifier for Connected EVM Chain
# 
# This script extracts deployed contract addresses from the EVM chain
# and updates the [connected_chain_evm] section in verifier_testing.toml.

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

# Setup verifier config
setup_verifier_config

# First, remove any commented-out EVM section from MVM-only tests
# This handles the case where MVM test ran before EVM test
sed -i '/^# MVM-only test:.*connected_chain_evm/d' "$VERIFIER_TESTING_CONFIG"
sed -i '/^# MVM-only test: name = "Connected EVM Chain"/d' "$VERIFIER_TESTING_CONFIG"
sed -i '/^# MVM-only test: rpc_url/d' "$VERIFIER_TESTING_CONFIG"
sed -i '/^# MVM-only test: escrow_contract_address/d' "$VERIFIER_TESTING_CONFIG"
sed -i '/^# MVM-only test: chain_id/d' "$VERIFIER_TESTING_CONFIG"
sed -i '/^# MVM-only test: verifier_address/d' "$VERIFIER_TESTING_CONFIG"
sed -i '/^# MVM-only test: *$/d' "$VERIFIER_TESTING_CONFIG"

# Add or update EVM chain section in verifier_testing.toml
if grep -q "^\[connected_chain_evm\]" "$VERIFIER_TESTING_CONFIG"; then
    # Update existing section
    sed -i "/\[connected_chain_evm\]/,/^\[/ s|rpc_url = .*|rpc_url = \"http://127.0.0.1:8545\"|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[connected_chain_evm\]/,/^\[/ s|escrow_contract_address = .*|escrow_contract_address = \"$CONTRACT_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[connected_chain_evm\]/,/^\[/ s|chain_id = .*|chain_id = 31337|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[connected_chain_evm\]/,/^\[/ s|verifier_address = .*|verifier_address = \"$VERIFIER_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
else
    # Add new section before [verifier] section
    if grep -q "^\[verifier\]" "$VERIFIER_TESTING_CONFIG"; then
        sed -i "/^\[verifier\]/i [connected_chain_evm]\nname = \"Connected EVM Chain\"\nrpc_url = \"http://127.0.0.1:8545\"\nescrow_contract_address = \"$CONTRACT_ADDRESS\"\nchain_id = 31337\nverifier_address = \"$VERIFIER_ADDRESS\"\n" "$VERIFIER_TESTING_CONFIG"
    else
        # Append at end of file
        echo "" >> "$VERIFIER_TESTING_CONFIG"
        echo "[connected_chain_evm]" >> "$VERIFIER_TESTING_CONFIG"
        echo "name = \"Connected EVM Chain\"" >> "$VERIFIER_TESTING_CONFIG"
        echo "rpc_url = \"http://127.0.0.1:8545\"" >> "$VERIFIER_TESTING_CONFIG"
        echo "escrow_contract_address = \"$CONTRACT_ADDRESS\"" >> "$VERIFIER_TESTING_CONFIG"
        echo "chain_id = 31337" >> "$VERIFIER_TESTING_CONFIG"
        echo "verifier_address = \"$VERIFIER_ADDRESS\"" >> "$VERIFIER_TESTING_CONFIG"
    fi
fi

# Comment out MVM chain configuration for EVM-only tests
# This prevents the verifier from trying to connect to MVM connected chain
# Note: TOML parser will ignore commented sections, so connected_chain_mvm will be None
sed -i '/^\[connected_chain_mvm\]/,/^\[connected_chain_evm\]/ {
    /^\[connected_chain_mvm\]/ s/^/# EVM-only test: /
    /^\[connected_chain_evm\]/! s/^/# EVM-only test: /
}' "$VERIFIER_TESTING_CONFIG"

log_and_echo "✅ Updated verifier_testing.toml with Connected EVM Chain addresses"
log_and_echo "   (MVM chain configuration commented out for EVM-only test)"
log_and_echo ""

