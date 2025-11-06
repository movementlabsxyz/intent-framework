#!/bin/bash

# Configure Verifier for EVM E2E Tests
# 
# This script extracts deployed contract addresses and updates verifier_testing.toml
# with the current deployment addresses for both Aptos Chain 1 and EVM Chain 3.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-evm"
cd "$PROJECT_ROOT"

log_and_echo "✅ Setup complete! Extracting module addresses..."
log_and_echo ""

# Extract deployed addresses from aptos profiles and update verifier.toml
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')

if [ -z "$CHAIN1_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract Chain 1 deployed module address"
    exit 1
fi

log_and_echo "   Chain 1 deployer: $CHAIN1_ADDRESS"

# Get EVM vault address
cd evm-intent-framework
VAULT_ADDRESS=$(grep -i "IntentVault deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-vault"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
cd ..

if [ -z "$VAULT_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract EVM vault address"
    exit 1
fi

log_and_echo "   EVM Vault: $VAULT_ADDRESS"

# Use verifier_testing.toml for tests - required, panic if not found
VERIFIER_TESTING_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

# Get verifier Ethereum address from config (derived from ECDSA public key)
log "   - Computing verifier Ethereum address from config..."
VERIFIER_ADDRESS=$(cd "$PROJECT_ROOT/trusted-verifier" && VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG" cargo run --bin get_verifier_eth_address 2>/dev/null | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')

if [ -z "$VERIFIER_ADDRESS" ]; then
    log_and_echo "   ⚠️  Warning: Could not compute verifier Ethereum address from config"
    log_and_echo "   Falling back to Hardhat account 0 (Deployer)"
    # Get Hardhat account 0 as fallback (Deployer is the verifier)
    cd evm-intent-framework
    VERIFIER_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=0 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')
    cd ..
    
    if [ -z "$VERIFIER_ADDRESS" ]; then
        VERIFIER_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"  # Hardhat default account 0
    fi
fi

log_and_echo "   EVM Verifier: $VERIFIER_ADDRESS"

# Export config path for Rust code to use (absolute path so tests can find it)
export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

# Update module addresses in verifier_testing.toml
sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

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

# Get Alice and Bob addresses and update known_accounts
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')

if [ -n "$ALICE_CHAIN1_ADDRESS" ] && [ -n "$BOB_CHAIN1_ADDRESS" ]; then
    sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

log_and_echo "✅ Updated verifier_testing.toml with deployed addresses"
log_and_echo ""

