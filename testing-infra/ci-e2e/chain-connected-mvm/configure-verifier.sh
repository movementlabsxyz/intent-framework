#!/bin/bash

# Configure Verifier for Connected Move VM Chain
# 
# This script adds the [connected_chain_mvm] section to verifier-e2e-ci-testing.toml.
# Must be called AFTER chain-hub/configure-verifier.sh which creates the base config.

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

# Get Requester address
REQUESTER_CHAIN2_ADDRESS=$(get_profile_address "requester-chain2")

# Config file path (created by chain-hub/configure-verifier.sh)
VERIFIER_E2E_CI_TESTING_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier-e2e-ci-testing.toml"

if [ ! -f "$VERIFIER_E2E_CI_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: Config file not found. Run chain-hub/configure-verifier.sh first."
    exit 1
fi

# Append connected_chain_mvm section to config (insert before [verifier] section)
# First, create a temp file with the new section
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << EOF

[connected_chain_mvm]
name = "Connected Move VM Chain"
rpc_url = "http://127.0.0.1:8082"
chain_id = 2
intent_module_address = "0x$CHAIN2_ADDRESS"
escrow_module_address = "0x$CHAIN2_ADDRESS"
known_accounts = ["$REQUESTER_CHAIN2_ADDRESS"]
EOF

# Insert the MVM section before [verifier] section
# Read the config, insert MVM section before [verifier], write back
awk -v mvm_section="$(cat $TEMP_FILE)" '
/^\[verifier\]/ { print mvm_section; print ""; }
{ print }
' "$VERIFIER_E2E_CI_TESTING_CONFIG" > "${VERIFIER_E2E_CI_TESTING_CONFIG}.tmp"
mv "${VERIFIER_E2E_CI_TESTING_CONFIG}.tmp" "$VERIFIER_E2E_CI_TESTING_CONFIG"

rm -f "$TEMP_FILE"

export VERIFIER_CONFIG_PATH="$VERIFIER_E2E_CI_TESTING_CONFIG"

log_and_echo "✅ Added Connected Move VM Chain section to verifier config"
log_and_echo ""

