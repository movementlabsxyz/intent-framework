#!/bin/bash

# Configure Verifier for E2E Tests
# 
# This script updates the verifier_testing.toml configuration with the current
# Requester, Solver, and deployer addresses for both hub and connected chains.

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
REQUESTER_CHAIN1_ADDRESS=$(get_profile_address "requester-chain1")
REQUESTER_CHAIN2_ADDRESS=$(get_profile_address "requester-chain2")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")
SOLVER_CHAIN2_ADDRESS=$(get_profile_address "solver-chain2")
CHAIN1_DEPLOY_ADDRESS=$(get_profile_address "intent-account-chain1")
CHAIN2_DEPLOY_ADDRESS=$(get_profile_address "intent-account-chain2")

log ""
log "📋 Chain Information:"
log "   Requester Chain 1: $REQUESTER_CHAIN1_ADDRESS"
log "   Requester Chain 2: $REQUESTER_CHAIN2_ADDRESS"
log "   Solver Chain 1: $SOLVER_CHAIN1_ADDRESS"
log "   Solver Chain 2: $SOLVER_CHAIN2_ADDRESS"
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

# Update hub_chain known_accounts (include both requester (Requester) and solver (Solver) - solver (Solver) fulfills intents)
sed -i "/\[hub_chain\]/,/\[connected_chain_mvm\]/ s|known_accounts = .*|known_accounts = [\"$REQUESTER_CHAIN1_ADDRESS\", \"$SOLVER_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"

# Update connected_chain_mvm known_accounts
sed -i "/\[connected_chain_mvm\]/,/\[connected_chain_evm\]/ s|known_accounts = .*|known_accounts = [\"$REQUESTER_CHAIN2_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"

# Comment out EVM chain configuration for MVM-only tests
# This prevents the verifier from trying to connect to EVM chain
# Note: TOML parser will ignore commented sections, so connected_chain_evm will be None
sed -i '/^\[connected_chain_evm\]/,/^\[verifier\]/ {
    /^\[connected_chain_evm\]/ s/^/# MVM-only test: /
    /^\[verifier\]/! s/^/# MVM-only test: /
}' "$VERIFIER_TESTING_CONFIG"

log "   ✅ Updated verifier_testing.toml with:"
log "      Chain 1 intent_module_address: 0x$CHAIN1_DEPLOY_ADDRESS"
log "      Chain 2 intent_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
log "      Chain 2 escrow_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
log "      Chain 1 known_accounts: [$REQUESTER_CHAIN1_ADDRESS, $SOLVER_CHAIN1_ADDRESS]"
log "      Chain 2 known_accounts: $REQUESTER_CHAIN2_ADDRESS"
log "      EVM chain configuration: commented out (MVM-only test)"

log ""
log_and_echo "✅ Verifier configuration updated"

