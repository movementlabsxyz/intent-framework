#!/bin/bash

# Setup Dual Chains and Test Alice/Bob Accounts
# This script:
# 1. Sets up dual Docker Aptos localnets
# 2. Creates and funds Alice and Bob accounts on both chains
# 3. Tests transfers between Alice and Bob on both chains
# Run this from the host machine (not inside Docker)

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-dual-chains"
cd "$PROJECT_ROOT"

# Expected funding amount in octas
# Note: aptos init funds accounts with 100000000, then we fund again with 100000000 = 200000000 total
EXPECTED_FUNDING_AMOUNT=200000000

log "🧪 Alice and Bob Account Testing - DUAL CHAINS"
log "=============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Create test accounts for Chain 1
log ""
log "👥 Creating test accounts for Chain 1..."

# Create alice account for Chain 1
log "Creating alice-chain1 account for Chain 1..."
if printf "\n" | aptos init --profile alice-chain1 --network local --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Alice-chain1 account created successfully on Chain 1"
else
    log_and_echo "❌ Failed to create Alice-chain1 account on Chain 1"
    exit 1
fi

# Create bob account for Chain 1
log "Creating bob-chain1 account for Chain 1..."
if printf "\n" | aptos init --profile bob-chain1 --network local --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Bob-chain1 account created successfully on Chain 1"
else
    log_and_echo "❌ Failed to create Bob-chain1 account on Chain 1"
    exit 1
fi

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

# Fund all accounts using common function
fund_and_verify_account "alice-chain1" "1" "Alice Chain 1" "$EXPECTED_FUNDING_AMOUNT" "ALICE_BALANCE"
fund_and_verify_account "bob-chain1" "1" "Bob Chain 1" "$EXPECTED_FUNDING_AMOUNT" "BOB_BALANCE"
fund_and_verify_account "alice-chain2" "2" "Alice Chain 2" "$EXPECTED_FUNDING_AMOUNT" "ALICE2_BALANCE"
fund_and_verify_account "bob-chain2" "2" "Bob Chain 2" "$EXPECTED_FUNDING_AMOUNT" "BOB2_BALANCE"

log_and_echo "✅ Accounts funded"

# Display initial balances using common function (variables already set above)
display_balances

log ""
log "% - - - - - - - - - - - SUMMARY - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

log ""
log "🎉 DUAL-CHAIN ALICE AND BOB SETUP COMPLETE!"
log "============================================"
log ""
log "📋 Account Information:"
log "Chain 1 (port 8080):"
log "   Alice: $ALICE_ADDRESS"
log "   Bob:   $BOB_ADDRESS"
log ""
log "Chain 2 (port 8082):"
log "   Alice: $ALICE2_ADDRESS"
log "   Bob:   $BOB2_ADDRESS"
log ""
log "🔗 Chain Endpoints:"
log "   Chain 1 REST API: http://127.0.0.1:8080/v1"
log "   Chain 1 Faucet:   http://127.0.0.1:8081"
log "   Chain 2 REST API: http://127.0.0.1:8082/v1"
log "   Chain 2 Faucet:   http://127.0.0.1:8083"
log ""
log "📡 API Examples:"
log "   Check Chain 1 status:    curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height'"
log "   Check Chain 2 status:    curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height'"
log "   Get Alice Chain 1:       curl -s http://127.0.0.1:8080/v1/accounts/$ALICE_ADDRESS"
log "   Get Alice Chain 2:       curl -s http://127.0.0.1:8082/v1/accounts/$ALICE2_ADDRESS"
log "   Fund Chain 1 account:    curl -X POST \"http://127.0.0.1:8081/mint?address=<ADDRESS>&amount=100000000\""
log "   Fund Chain 2 account:    curl -X POST \"http://127.0.0.1:8083/mint?address=<ADDRESS>&amount=100000000\""
log ""
log "📋 Useful Commands:"
log "   Stop chains:     ./testing-infra/connected-chain-apt/stop-dual-chains.sh"
log "   View profiles:   aptos config show-profiles"
log "   Test Chain 1:    aptos account balance --profile alice"
log "   Test Chain 2:    aptos account balance --profile alice-chain2"
log ""
log "✨ Ready for cross-chain testing!"

