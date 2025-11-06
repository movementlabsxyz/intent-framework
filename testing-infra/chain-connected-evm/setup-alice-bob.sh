#!/bin/bash

# Setup EVM Chain and Test Alice/Bob Accounts
# This script:
# 1. Sets up Hardhat local EVM node
# 2. Verifies Alice and Bob accounts (Hardhat default accounts 0 and 1)
# 3. Tests basic transfers between Alice and Bob
# Run this from the host machine

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-evm-alice-bob"
cd "$PROJECT_ROOT"

log "🧪 Alice and Bob Account Testing - EVM CHAIN"
log "=============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Wait for node to be fully ready (assumes setup-chain.sh was already run)
log "⏳ Waiting for node to be fully ready..."
sleep 5

# Verify EVM chain is running
log "🔍 Verifying EVM chain is running..."
if ! curl -s -X POST http://127.0.0.1:8545 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    >/dev/null 2>&1; then
    log_and_echo "❌ Error: EVM chain failed to start on port 8545"
    exit 1
fi

log ""
log "% - - - - - - - - - - - ACCOUNTS - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

log ""
log "📋 Hardhat Default Accounts:"
log "   Deployer/Verifier = Account 0 (signer index 0)"
log "   Alice             = Account 1 (signer index 1)"
log "   Bob               = Account 2 (signer index 2)"

# Get account addresses using Hardhat
cd evm-intent-framework
log ""
log "🔍 Getting Alice and Bob addresses..."

ACCOUNTS_OUTPUT=$(nix develop -c bash -c "npx hardhat run scripts/get-accounts.js" 2>&1)

if [ $? -ne 0 ]; then
    log_and_echo "❌ Error: Failed to get account addresses"
    echo "$ACCOUNTS_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

ALICE_ADDRESS=$(echo "$ACCOUNTS_OUTPUT" | grep "^ALICE_ADDRESS=" | cut -d'=' -f2 | tr -d '\n')
BOB_ADDRESS=$(echo "$ACCOUNTS_OUTPUT" | grep "^BOB_ADDRESS=" | cut -d'=' -f2 | tr -d '\n')

cd ..

if [ -z "$ALICE_ADDRESS" ] || [ -z "$BOB_ADDRESS" ]; then
    log_and_echo "❌ Error: Failed to extract account addresses from output"
    echo "$ACCOUNTS_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

log "   ✅ Alice (Account 1): $ALICE_ADDRESS"
log "   ✅ Bob (Account 2):   $BOB_ADDRESS"

log ""
log "% - - - - - - - - - - - BALANCES - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Check initial balances
log ""
log "💰 Checking initial balances..."

cd evm-intent-framework
BALANCES_OUTPUT=$(nix develop -c bash -c "npx hardhat run scripts/get-accounts.js" 2>&1)

if [ $? -ne 0 ]; then
    log_and_echo "❌ Error: Failed to get account balances"
    echo "$BALANCES_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

ALICE_BALANCE=$(echo "$BALANCES_OUTPUT" | grep "^ALICE_BALANCE=" | cut -d'=' -f2 | tr -d '\n')
BOB_BALANCE=$(echo "$BALANCES_OUTPUT" | grep "^BOB_BALANCE=" | cut -d'=' -f2 | tr -d '\n')

cd ..

if [ -z "$ALICE_BALANCE" ] || [ -z "$BOB_BALANCE" ]; then
    log_and_echo "❌ Error: Failed to extract account balances from output"
    echo "$BALANCES_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

log "   Alice balance: $ALICE_BALANCE wei (should be 10000 ETH = 10000000000000000000000 wei)"
log "   Bob balance:   $BOB_BALANCE wei (should be 10000 ETH = 10000000000000000000000 wei)"

log ""
log "% - - - - - - - - - - - TEST TRANSFER - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Test transfer from Alice to Bob
log ""
log "🧪 Testing transfer from Alice to Bob..."

cd evm-intent-framework
TRANSFER_RESULT=$(nix develop -c bash -c "npx hardhat run scripts/test-transfer.js" 2>&1)

cd ..

if echo "$TRANSFER_RESULT" | grep -q "SUCCESS"; then
    log "   ✅ Transfer successful!"
else
    log_and_echo "   ❌ Transfer failed!"
    echo "$TRANSFER_RESULT" >> "$LOG_FILE"
    exit 1
fi

log ""
log "🎉 All EVM chain setup and testing complete!"
log ""
log "📋 Summary:"
log "   EVM Chain:     http://127.0.0.1:8545"
log "   Chain ID:      31337"
log "   Alice (Acc 1): $ALICE_ADDRESS"
log "   Bob (Acc 2):   $BOB_ADDRESS"
log ""
log "📋 Useful commands:"
log "   Stop chain:    ./testing-infra/chain-connected-evm/stop-chain.sh"
log ""
log "✨ Script completed!"

