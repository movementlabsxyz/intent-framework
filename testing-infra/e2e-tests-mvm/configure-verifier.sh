#!/bin/bash

# Configure Verifier for E2E Tests
# 
# This script updates the verifier_testing.toml configuration with the current
# Alice, Bob, and deployer addresses for both hub and connected chains.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "configure-verifier-e2e"
cd "$PROJECT_ROOT"

log ""
log "🔧 Configuring Verifier for E2E Tests"
log "======================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

# ============================================================================
# SECTION 1: GET ADDRESSES
# ============================================================================
ALICE_CHAIN1_ADDRESS=$(get_profile_address "alice-chain1")
ALICE_CHAIN2_ADDRESS=$(get_profile_address "alice-chain2")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")
BOB_CHAIN2_ADDRESS=$(get_profile_address "bob-chain2")
CHAIN1_DEPLOY_ADDRESS=$(get_profile_address "intent-account-chain1")
CHAIN2_DEPLOY_ADDRESS=$(get_profile_address "intent-account-chain2")

log ""
log "📋 Chain Information:"
log "   Alice Chain 1: $ALICE_CHAIN1_ADDRESS"
log "   Alice Chain 2: $ALICE_CHAIN2_ADDRESS"
log "   Bob Chain 1: $BOB_CHAIN1_ADDRESS"
log "   Bob Chain 2: $BOB_CHAIN2_ADDRESS"
log "   Chain 1 Deployer: $CHAIN1_DEPLOY_ADDRESS"
log "   Chain 2 Deployer: $CHAIN2_DEPLOY_ADDRESS"

# ============================================================================
# SECTION 2: UPDATE VERIFIER CONFIGURATION
# ============================================================================
log ""
log "   - Updating verifier configuration..."
setup_verifier_config

# Update hub_chain intent_module_address
sed -i "/\[hub_chain\]/,/\[connected_chain_mvm\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_DEPLOY_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Update connected_chain_mvm intent_module_address
sed -i "/\[connected_chain_mvm\]/,/\[verifier\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN2_DEPLOY_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Update connected_chain_mvm escrow_module_address (same as intent_module_address)
sed -i "/\[connected_chain_mvm\]/,/\[verifier\]/ s|escrow_module_address = .*|escrow_module_address = \"0x$CHAIN2_DEPLOY_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Update hub_chain known_accounts (include both requester (Alice) and solver (Bob) - solver (Bob) fulfills intents)
sed -i "/\[hub_chain\]/,/\[connected_chain_mvm\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"

# Update connected_chain_mvm known_accounts
sed -i "/\[connected_chain_mvm\]/,/\[verifier\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN2_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"

log "   ✅ Updated verifier_testing.toml with:"
log "      Chain 1 intent_module_address: 0x$CHAIN1_DEPLOY_ADDRESS"
log "      Chain 2 intent_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
log "      Chain 2 escrow_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
log "      Chain 1 known_accounts: [$ALICE_CHAIN1_ADDRESS, $BOB_CHAIN1_ADDRESS]"
log "      Chain 2 known_accounts: $ALICE_CHAIN2_ADDRESS"

log ""
log_and_echo "✅ Verifier configuration updated"

