#!/bin/bash

# Configure Verifier for Connected EVM Chain
# 
# This script extracts deployed contract addresses from the EVM chain
# and updates the [evm_chain] section in verifier_testing.toml.

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

# Get EVM vault address
VAULT_ADDRESS=$(extract_vault_address)
log_and_echo "   EVM Vault: $VAULT_ADDRESS"

# Get verifier Ethereum address (Hardhat account 0)
log "   - Getting verifier Ethereum address (Hardhat account 0)..."
VERIFIER_ADDRESS=$(get_hardhat_account_address "0")
log_and_echo "   EVM Verifier: $VERIFIER_ADDRESS"

# Setup verifier config
setup_verifier_config

# Add or update EVM chain section in verifier_testing.toml
if grep -q "^\[evm_chain\]" "$VERIFIER_TESTING_CONFIG"; then
    # Update existing section
    sed -i "/\[evm_chain\]/,/^\[/ s|rpc_url = .*|rpc_url = \"http://127.0.0.1:8545\"|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[evm_chain\]/,/^\[/ s|vault_address = .*|vault_address = \"$VAULT_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[evm_chain\]/,/^\[/ s|chain_id = .*|chain_id = 31337|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[evm_chain\]/,/^\[/ s|verifier_address = .*|verifier_address = \"$VERIFIER_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
else
    # Add new section before [verifier] section
    if grep -q "^\[verifier\]" "$VERIFIER_TESTING_CONFIG"; then
        sed -i "/^\[verifier\]/i [evm_chain]\nrpc_url = \"http://127.0.0.1:8545\"\nvault_address = \"$VAULT_ADDRESS\"\nchain_id = 31337\nverifier_address = \"$VERIFIER_ADDRESS\"\n" "$VERIFIER_TESTING_CONFIG"
    else
        # Append at end of file
        echo "" >> "$VERIFIER_TESTING_CONFIG"
        echo "[evm_chain]" >> "$VERIFIER_TESTING_CONFIG"
        echo "rpc_url = \"http://127.0.0.1:8545\"" >> "$VERIFIER_TESTING_CONFIG"
        echo "vault_address = \"$VAULT_ADDRESS\"" >> "$VERIFIER_TESTING_CONFIG"
        echo "chain_id = 31337" >> "$VERIFIER_TESTING_CONFIG"
        echo "verifier_address = \"$VERIFIER_ADDRESS\"" >> "$VERIFIER_TESTING_CONFIG"
    fi
fi

log_and_echo "✅ Updated verifier_testing.toml with Connected EVM Chain addresses"
log_and_echo ""

