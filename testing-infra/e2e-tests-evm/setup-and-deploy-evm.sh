#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-and-deploy-evm"
cd "$PROJECT_ROOT"

log "🚀 EVM CHAIN - SETUP AND DEPLOY"
log "==============================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "🔗 Step 1: Setting up EVM Chain (Hardhat node)..."
log " ============================================="
./testing-infra/connected-chain-evm/setup-evm-chain.sh

if [ $? -ne 0 ]; then
    log_and_echo "❌ Failed to setup EVM chain"
    exit 1
fi

log ""
log "🔍 Step 1.5: Verifying EVM accounts are funded..."
log " ============================================="

# Wait a bit to ensure Hardhat node is fully ready
sleep 2

# Get Alice and Bob addresses and verify they have funds
# Note: Use absolute path to evm-intent-framework since nix develop might start in different directory
EVM_DIR="$PROJECT_ROOT/evm-intent-framework"

log "   - Getting Alice address (Account 0)..."
ALICE_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$EVM_DIR' && ACCOUNT_INDEX=0 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')

log "   - Getting Bob address (Account 1)..."
BOB_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$EVM_DIR' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')

if [ -z "$ALICE_ADDRESS" ] || [ -z "$BOB_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Failed to get EVM account addresses"
    log_and_echo "   Alice address: ${ALICE_ADDRESS:-empty}"
    log_and_echo "   Bob address: ${BOB_ADDRESS:-empty}"
    log_and_echo "   EVM chain may not be properly initialized"
    log_and_echo "   Testing Hardhat connection..."
    nix develop "$PROJECT_ROOT" -c bash -c "cd '$EVM_DIR' && npx hardhat run scripts/test-accounts.js --network localhost" 2>&1
    exit 1
fi

log "   ✅ Alice address: $ALICE_ADDRESS"
log "   ✅ Bob address: $BOB_ADDRESS"

# Verify balances (Hardhat default accounts should have 10000 ETH each = 10000000000000000000000 wei)
log "   - Getting Alice balance..."
ALICE_BALANCE_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$EVM_DIR' && ACCOUNT_INDEX=0 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
# Extract balance - look for a line that's purely numeric (the balance) and take the last one
# This handles cases where there might be line numbers or other numeric output
ALICE_BALANCE=$(echo "$ALICE_BALANCE_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')

# Check if the script failed (error messages would indicate failure)
if echo "$ALICE_BALANCE_OUTPUT" | grep -qi "error\|cannot connect\|ECONNREFUSED"; then
    log_and_echo "❌ ERROR: Failed to get Alice balance - Hardhat node may not be ready"
    log_and_echo "   Error output: $ALICE_BALANCE_OUTPUT"
    exit 1
fi

log "   DEBUG: Alice balance extracted: '$ALICE_BALANCE'"

log "   - Getting Bob balance..."
BOB_BALANCE_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$EVM_DIR' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
# Extract balance - look for a line that's purely numeric (the balance) and take the last one
BOB_BALANCE=$(echo "$BOB_BALANCE_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')

# Check if the script failed (error messages would indicate failure)
if echo "$BOB_BALANCE_OUTPUT" | grep -qi "error\|cannot connect\|ECONNREFUSED"; then
    log_and_echo "❌ ERROR: Failed to get Bob balance - Hardhat node may not be ready"
    log_and_echo "   Error output: $BOB_BALANCE_OUTPUT"
    exit 1
fi

log "   DEBUG: Bob balance extracted: '$BOB_BALANCE'"

# Panic if we can't get balances
if [ -z "$ALICE_BALANCE" ] || [ -z "$BOB_BALANCE" ]; then
    log_and_echo "❌ ERROR: Failed to get EVM account balances"
    log_and_echo "   Alice balance output: $ALICE_BALANCE_OUTPUT"
    log_and_echo "   Bob balance output: $BOB_BALANCE_OUTPUT"
    log_and_echo "   EVM chain may not be responding properly"
    exit 1
fi

# Panic if balances are 0 (Hardhat default accounts should have 10000 ETH each)
# Use explicit string comparison and check for empty as well
if [ -z "$ALICE_BALANCE" ] || [ "$ALICE_BALANCE" = "0" ] || [ "$ALICE_BALANCE" = "" ]; then
    log_and_echo "❌ ERROR: Alice (Account 0) has ZERO or empty balance on EVM chain"
    log_and_echo "   Balance extracted: '$ALICE_BALANCE'"
    log_and_echo "   Balance output: $ALICE_BALANCE_OUTPUT"
    log_and_echo "   Address: $ALICE_ADDRESS"
    log_and_echo "   Hardhat default accounts should have 10000 ETH each"
    log_and_echo "   EVM chain may not be properly initialized"
    exit 1
fi

if [ -z "$BOB_BALANCE" ] || [ "$BOB_BALANCE" = "0" ] || [ "$BOB_BALANCE" = "" ]; then
    log_and_echo "❌ ERROR: Bob (Account 1) has ZERO or empty balance on EVM chain"
    log_and_echo "   Balance extracted: '$BOB_BALANCE'"
    log_and_echo "   Balance output: $BOB_BALANCE_OUTPUT"
    log_and_echo "   Address: $BOB_ADDRESS"
    log_and_echo "   Hardhat default accounts should have 10000 ETH each"
    log_and_echo "   EVM chain may not be properly initialized"
    exit 1
fi

# Check if balances are sufficient (should be at least 1 ETH = 1000000000000000000 wei)
MIN_BALANCE="1000000000000000000"

# Use awk for numeric comparison (handles large numbers better)
ALICE_SUFFICIENT=$(echo "$ALICE_BALANCE $MIN_BALANCE" | awk '{if ($1 >= $2) print "1"; else print "0"}')
BOB_SUFFICIENT=$(echo "$BOB_BALANCE $MIN_BALANCE" | awk '{if ($1 >= $2) print "1"; else print "0"}')

if [ "$ALICE_SUFFICIENT" = "0" ]; then
    log_and_echo "❌ ERROR: Alice (Account 0) balance insufficient"
    log_and_echo "   Balance: $ALICE_BALANCE wei"
    log_and_echo "   Required: At least 1 ETH ($MIN_BALANCE wei)"
    log_and_echo "   Address: $ALICE_ADDRESS"
    exit 1
fi

if [ "$BOB_SUFFICIENT" = "0" ]; then
    log_and_echo "❌ ERROR: Bob (Account 1) balance insufficient"
    log_and_echo "   Balance: $BOB_BALANCE wei"
    log_and_echo "   Required: At least 1 ETH ($MIN_BALANCE wei)"
    log_and_echo "   Address: $BOB_ADDRESS"
    exit 1
fi

log "   ✅ Alice (Account 0): $ALICE_ADDRESS - Balance verified"
log "   ✅ Bob (Account 1):   $BOB_ADDRESS - Balance verified"

# Display EVM chain balances
display_balances

log ""
log "📦 Step 2: Deploying IntentVault to EVM chain..."
log " ============================================="
./testing-infra/e2e-tests-evm/deploy-vault.sh

if [ $? -ne 0 ]; then
    log_and_echo "❌ Failed to deploy IntentVault"
    exit 1
fi

# Extract vault address from deployment logs
VAULT_ADDRESS=$(grep -i "IntentVault deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-vault"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')

if [ -z "$VAULT_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract vault address from deployment logs"
    log_and_echo "   This is required for verifier configuration"
    log_and_echo "   Check deployment logs in: $PROJECT_ROOT/tmp/intent-framework-logs/"
    log_and_echo "   Deployment may have failed - check deploy-vault logs for errors"
    exit 1
else
    log "   ✅ IntentVault deployed at: $VAULT_ADDRESS"
fi

# Get verifier address (Hardhat account 1 - same as Bob)
VERIFIER_ADDRESS="$BOB_ADDRESS"

if [ -z "$VERIFIER_ADDRESS" ]; then
    # Fallback: Hardhat account 1 address (known default)
    VERIFIER_ADDRESS="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
    log "   ℹ️  Using default Hardhat verifier address: $VERIFIER_ADDRESS"
else
    log "   ✅ Verifier address: $VERIFIER_ADDRESS"
fi

log_and_echo "✅ EVM contracts deployed"

log ""
log "🎉 EVM DEPLOYMENT COMPLETE!"
log "==========================="
log "EVM Chain:"
log "   RPC URL:  http://127.0.0.1:8545"
log "   Chain ID: 31337"
log "   Vault:    $VAULT_ADDRESS"
log "   Verifier: $VERIFIER_ADDRESS"
log ""
log "📡 API Examples:"
log "   Check EVM Chain:    curl -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
log ""
log "📋 Useful commands:"
log "   Stop EVM chain:  ./testing-infra/connected-chain-evm/stop-evm-chain.sh"

log ""
log "✨ EVM setup and deployment script completed!"
