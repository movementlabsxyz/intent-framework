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
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/utils.sh"

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
if ! check_evm_chain_running; then
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
log ""
log "🔍 Getting Alice and Bob addresses..."

ALICE_ADDRESS=$(get_hardhat_account_address "1")
BOB_ADDRESS=$(get_hardhat_account_address "2")

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
log "% - - - - - - - - - - - BURN EXCESS ETH - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Burn excess ETH from Alice and Bob, leaving only 2 ETH each
# This ensures half of Bob's balance (1 ETH) is within u64::MAX for Move contracts
log ""
log "🔥 Burning excess ETH from Alice and Bob (leaving 2 ETH each)..."

cd evm-intent-framework

# Burn from Alice (Account 1)
log "   - Burning excess ETH from Alice (Account 1)..."
KEEP_AMOUNT_WEI="2000000000000000000"  # 2 ETH
ALICE_BURN_RESULT=$(nix develop -c bash -c "ACCOUNT_INDEX=1 KEEP_AMOUNT_WEI='$KEEP_AMOUNT_WEI' npx hardhat run scripts/burn-excess-eth.js --network localhost" 2>&1)

if echo "$ALICE_BURN_RESULT" | grep -q "SUCCESS"; then
    log "     ✅ Alice excess ETH burned"
else
    log_and_echo "     ❌ Failed to burn Alice's excess ETH"
    echo "$ALICE_BURN_RESULT" >> "$LOG_FILE"
    exit 1
fi

# Burn from Bob (Account 2)
log "   - Burning excess ETH from Bob (Account 2)..."
BOB_BURN_RESULT=$(nix develop -c bash -c "ACCOUNT_INDEX=2 KEEP_AMOUNT_WEI='$KEEP_AMOUNT_WEI' npx hardhat run scripts/burn-excess-eth.js --network localhost" 2>&1)

if echo "$BOB_BURN_RESULT" | grep -q "SUCCESS"; then
    log "     ✅ Bob excess ETH burned"
else
    log_and_echo "     ❌ Failed to burn Bob's excess ETH"
    echo "$BOB_BURN_RESULT" >> "$LOG_FILE"
    exit 1
fi

cd ..

# Verify final balances
log ""
log "💰 Verifying final balances..."

cd evm-intent-framework
FINAL_BALANCES_OUTPUT=$(nix develop -c bash -c "npx hardhat run scripts/get-accounts.js" 2>&1)

if [ $? -ne 0 ]; then
    log_and_echo "❌ Error: Failed to get final account balances"
    echo "$FINAL_BALANCES_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

ALICE_FINAL_BALANCE=$(echo "$FINAL_BALANCES_OUTPUT" | grep "^ALICE_BALANCE=" | cut -d'=' -f2 | tr -d '\n')
BOB_FINAL_BALANCE=$(echo "$FINAL_BALANCES_OUTPUT" | grep "^BOB_BALANCE=" | cut -d'=' -f2 | tr -d '\n')

cd ..

if [ -z "$ALICE_FINAL_BALANCE" ] || [ -z "$BOB_FINAL_BALANCE" ]; then
    log_and_echo "❌ Error: Failed to extract final account balances"
    echo "$FINAL_BALANCES_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

log "   Alice final balance: $ALICE_FINAL_BALANCE wei (should be ~2 ETH = 2000000000000000000 wei)"
log "   Bob final balance:   $BOB_FINAL_BALANCE wei (should be ~2 ETH = 2000000000000000000 wei)"

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

