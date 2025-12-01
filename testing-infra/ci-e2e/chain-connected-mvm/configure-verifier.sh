#!/bin/bash

# Configure Verifier for Connected Move VM Chain
# 
# This script extracts deployed contract addresses from Chain 2 (Connected Move VM Chain)
# and updates the [connected_chain_mvm] section in verifier_testing.toml.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-connected-mvm"
cd "$PROJECT_ROOT"

log_and_echo "✅ Configuring verifier for Connected Move VM Chain..."
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

# Update connected_chain_mvm section in verifier_testing.toml
sed -i "/\[connected_chain_mvm\]/,/\[verifier\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN2_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
sed -i "/\[connected_chain_mvm\]/,/\[verifier\]/ s|escrow_module_address = .*|escrow_module_address = \"0x$CHAIN2_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Get Requester address and update known_accounts
REQUESTER_CHAIN2_ADDRESS=$(get_profile_address "requester-chain2")

if [ -n "$REQUESTER_CHAIN2_ADDRESS" ]; then
    sed -i "/\[connected_chain_mvm\]/,/\[verifier\]/ s|known_accounts = .*|known_accounts = [\"$REQUESTER_CHAIN2_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

log_and_echo "✅ Updated verifier_testing.toml with Connected Move VM Chain addresses"
log_and_echo ""

