#!/bin/bash

# Configure Verifier for Connected Aptos Chain
# 
# This script extracts deployed contract addresses from Chain 2 (Connected Aptos Chain)
# and updates the [connected_chain_apt] section in verifier_testing.toml.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_apt.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-connected-apt"
cd "$PROJECT_ROOT"

log_and_echo "✅ Configuring verifier for Connected Aptos Chain..."
log_and_echo ""

# Extract deployed address from aptos profile
CHAIN2_ADDRESS=$(get_profile_address "intent-account-chain2")

if [ -z "$CHAIN2_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract Chain 2 deployed module address"
    exit 1
fi

log_and_echo "   Chain 2 deployer: $CHAIN2_ADDRESS"

# Setup verifier config
setup_verifier_config

# Update connected_chain_apt section in verifier_testing.toml
sed -i "/\[connected_chain_apt\]/,/\[verifier\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN2_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
sed -i "/\[connected_chain_apt\]/,/\[verifier\]/ s|escrow_module_address = .*|escrow_module_address = \"0x$CHAIN2_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Get Alice address and update known_accounts
ALICE_CHAIN2_ADDRESS=$(get_profile_address "alice-chain2")

if [ -n "$ALICE_CHAIN2_ADDRESS" ]; then
    sed -i "/\[connected_chain_apt\]/,/\[verifier\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN2_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

log_and_echo "✅ Updated verifier_testing.toml with Connected Aptos Chain addresses"
log_and_echo ""

