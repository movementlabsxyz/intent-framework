#!/bin/bash

# Setup Hub Chain Test Alice/Bob Accounts
# This script:
# 1. Creates and funds Alice and Bob accounts on Chain 1 (hub chain)
# Run this from the host machine (not inside Docker)

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-alice-bob-hub"
cd "$PROJECT_ROOT"

# Expected funding amount in octas
# Note: aptos init funds accounts with 100000000, then we fund again with 100000000 = 200000000 total
EXPECTED_FUNDING_AMOUNT=200000000

log "🧪 Alice and Bob Account Setup - HUB CHAIN (Chain 1)"
log "====================================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Create test accounts for Chain 1
log ""
log "👥 Creating test accounts for Chain 1..."

# Create alice account for Chain 1
log "Creating alice-chain1 account for Chain 1..."
init_aptos_profile "alice-chain1" "1" "$LOG_FILE"

# Create bob account for Chain 1
log "Creating bob-chain1 account for Chain 1..."
init_aptos_profile "bob-chain1" "1" "$LOG_FILE"

log ""
log "% - - - - - - - - - - - FUNDING - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Fund Chain 1 accounts using common function
fund_and_verify_account "alice-chain1" "1" "Alice Chain 1" "$EXPECTED_FUNDING_AMOUNT" "ALICE_BALANCE"
fund_and_verify_account "bob-chain1" "1" "Bob Chain 1" "$EXPECTED_FUNDING_AMOUNT" "BOB_BALANCE"

log_and_echo "✅ Hub chain accounts funded"

log ""
log "🎉 HUB CHAIN ALICE AND BOB SETUP COMPLETE!"
log "=========================================="
log "✨ Hub chain accounts ready!"

