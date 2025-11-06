#!/bin/bash

# Setup Connected Chain Test Alice/Bob Accounts
# This script:
# 1. Creates and funds Alice and Bob accounts on Chain 2 (connected chain)
# Run this from the host machine (not inside Docker)

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-alice-bob-connected"
cd "$PROJECT_ROOT"

# Expected funding amount in octas
# Note: aptos init funds accounts with 100000000, then we fund again with 100000000 = 200000000 total
EXPECTED_FUNDING_AMOUNT=200000000

log "🧪 Alice and Bob Account Setup - CONNECTED CHAIN (Chain 2)"
log "==========================================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Create test accounts for Chain 2
log ""
log "👥 Creating test accounts for Chain 2..."

# Create alice account for Chain 2
log "Creating alice-chain2 account for Chain 2..."
if printf "\n" | aptos init --profile alice-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Alice-chain2 account created successfully on Chain 2"
else
    log_and_echo "❌ Failed to create Alice-chain2 account on Chain 2"
    exit 1
fi

# Create bob account for Chain 2
log "Creating bob-chain2 account for Chain 2..."
if printf "\n" | aptos init --profile bob-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Bob-chain2 account created successfully on Chain 2"
else
    log_and_echo "❌ Failed to create Bob-chain2 account on Chain 2"
    exit 1
fi

log ""
log "% - - - - - - - - - - - FUNDING - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Fund Chain 2 accounts using common function
fund_and_verify_account "alice-chain2" "2" "Alice Chain 2" "$EXPECTED_FUNDING_AMOUNT" "ALICE2_BALANCE"
fund_and_verify_account "bob-chain2" "2" "Bob Chain 2" "$EXPECTED_FUNDING_AMOUNT" "BOB2_BALANCE"

log_and_echo "✅ Connected chain accounts funded"

log ""
log "🎉 CONNECTED CHAIN ALICE AND BOB SETUP COMPLETE!"
log "=================================================="
log "✨ Connected chain accounts ready!"
