#!/bin/bash

# Configure Verifier for Connected EVM Chain
# 
# This script extracts deployed contract addresses from the EVM chain
# and updates the [evm_chain] section in verifier_testing.toml.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-connected-evm"
cd "$PROJECT_ROOT"

log_and_echo "✅ Configuring verifier for Connected EVM Chain..."
log_and_echo ""

# Get EVM vault address
cd evm-intent-framework
VAULT_ADDRESS=$(grep -i "IntentVault deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-contract"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
cd ..

if [ -z "$VAULT_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract EVM vault address"
    exit 1
fi

log_and_echo "   EVM Vault: $VAULT_ADDRESS"

# Get verifier Ethereum address (Hardhat account 0)
log "   - Getting verifier Ethereum address (Hardhat account 0)..."
cd evm-intent-framework
VERIFIER_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=0 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')
cd ..

if [ -z "$VERIFIER_ADDRESS" ]; then
    log_and_echo "   ❌ ERROR: Could not get verifier Ethereum address from Hardhat account 0"
    log_and_echo "   ❌ Cannot proceed without a valid verifier address"
    log_and_echo "   ❌ Please ensure Hardhat node is running"
    exit 1
fi

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

