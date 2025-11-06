#!/bin/bash

# Configure Verifier for Hub Chain
# 
# This script extracts deployed contract addresses from Chain 1 (Hub Chain)
# and updates the [hub_chain] section in verifier_testing.toml.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-hub"
cd "$PROJECT_ROOT"

log_and_echo "✅ Configuring verifier for Hub Chain..."
log_and_echo ""

# Extract deployed address from aptos profile
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')

if [ -z "$CHAIN1_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract Chain 1 deployed module address"
    exit 1
fi

log_and_echo "   Chain 1 deployer: $CHAIN1_ADDRESS"

# Use verifier_testing.toml for tests - required, panic if not found
VERIFIER_TESTING_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

# Export config path for Rust code to use (absolute path so tests can find it)
export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

# Update hub_chain section in verifier_testing.toml
sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Get Alice and Bob addresses and update known_accounts
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')

if [ -n "$ALICE_CHAIN1_ADDRESS" ] && [ -n "$BOB_CHAIN1_ADDRESS" ]; then
    sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

log_and_echo "✅ Updated verifier_testing.toml with Hub Chain addresses"
log_and_echo ""

