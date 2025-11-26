#!/bin/bash

# Setup Connected Chain Test Requester/Solver Accounts
# This script:
# 1. Creates and funds Requester and Solver accounts on Chain 2 (connected chain)
# Run this from the host machine (not inside Docker)

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-requester-solver-connected"
cd "$PROJECT_ROOT"

# Expected funding amount in octas
# Note: aptos init funds accounts with 100000000, then we fund again with 100000000 = 200000000 total
EXPECTED_FUNDING_AMOUNT=200000000

log "🧪 Requester and Solver Account Setup - CONNECTED CHAIN (Chain 2)"
log "==========================================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Create test accounts for Chain 2
log ""
log "👥 Creating test accounts for Chain 2..."

# Create requester account for Chain 2
log "Creating requester-chain2 account for Chain 2..."
init_aptos_profile "requester-chain2" "2" "$LOG_FILE"

# Create solver account for Chain 2
log "Creating solver-chain2 account for Chain 2..."
init_aptos_profile "solver-chain2" "2" "$LOG_FILE"

# Create test-tokens account for Chain 2 (for USDxyz deployment)
log "Creating test-tokens-chain2 account for Chain 2..."
init_aptos_profile "test-tokens-chain2" "2" "$LOG_FILE"

log ""
log "% - - - - - - - - - - - FUNDING - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Fund Chain 2 accounts using common function
fund_and_verify_account "requester-chain2" "2" "Requester Chain 2" "$EXPECTED_FUNDING_AMOUNT" "REQUESTER2_BALANCE"
fund_and_verify_account "solver-chain2" "2" "Solver Chain 2" "$EXPECTED_FUNDING_AMOUNT" "SOLVER2_BALANCE"

log_and_echo "✅ Connected chain accounts funded"

log ""
log "🎉 CONNECTED CHAIN REQUESTER AND SOLVER SETUP COMPLETE!"
log "=================================================="
log "✨ Connected chain accounts ready!"
