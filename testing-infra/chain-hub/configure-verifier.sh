#!/bin/bash

# Configure Verifier for Hub Chain
# 
# This script extracts deployed contract addresses from Chain 1 (Hub Chain)
# and updates the [hub_chain] section in verifier_testing.toml.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-hub"
cd "$PROJECT_ROOT"

log_and_echo "✅ Configuring verifier for Hub Chain..."
log_and_echo ""

# Extract deployed address from aptos profile
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")

if [ -z "$CHAIN1_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract Chain 1 deployed module address"
    exit 1
fi

log_and_echo "   Chain 1 deployer: $CHAIN1_ADDRESS"

# Setup verifier config
setup_verifier_config

# Update hub_chain section in verifier_testing.toml
sed -i "/\[hub_chain\]/,/\[connected_chain_mvm\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Get Alice and Bob addresses and update known_accounts
ALICE_CHAIN1_ADDRESS=$(get_profile_address "alice-chain1")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")

if [ -n "$ALICE_CHAIN1_ADDRESS" ] && [ -n "$BOB_CHAIN1_ADDRESS" ]; then
    sed -i "/\[hub_chain\]/,/\[connected_chain_mvm\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

log_and_echo "✅ Updated verifier_testing.toml with Hub Chain addresses"
log_and_echo ""

