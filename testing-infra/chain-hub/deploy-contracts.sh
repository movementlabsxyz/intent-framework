#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "deploy-contracts-hub"
cd "$PROJECT_ROOT"

log "🚀 DEPLOY CONTRACTS - HUB CHAIN (Chain 1)"
log "=========================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "⚙️  Configuring Aptos CLI for Chain 1..."

# Clean up any existing profile to ensure fresh address each run
log "🧹 Cleaning up existing CLI profile..."
cleanup_aptos_profile "intent-account-chain1" "$LOG_FILE"

# Configure Chain 1 (port 8080)
log "   - Configuring Chain 1 (port 8080)..."
init_aptos_profile "intent-account-chain1" "1" "$LOG_FILE"

log ""
log "📦 Deploying contracts to Chain 1..."
log "   - Getting account address for Chain 1..."
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")

log "   - Deploying to Chain 1 with address: $CHAIN1_ADDRESS"
cd move-intent-framework
aptos move publish --dev --profile intent-account-chain1 --named-addresses mvmt_intent=$CHAIN1_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Chain 1 deployment successful!"
    log_and_echo "✅ Hub chain contracts deployed"
else
    log_and_echo "   ❌ Chain 1 deployment failed!"
    log_and_echo "   Log file contents:"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    cat "$LOG_FILE"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
fi

cd ..

# Initialize solver registry (idempotent - will fail silently if already initialized)
log ""
log "🔧 Initializing solver registry..."
initialize_solver_registry "intent-account-chain1" "$CHAIN1_ADDRESS" "$LOG_FILE"

# Deploy USDxyz test token
log ""
log "💵 Deploying USDxyz test token to Chain 1..."

TEST_TOKENS_CHAIN1_ADDRESS=$(get_profile_address "test-tokens-chain1")

log "   - Deploying USDxyz with address: $TEST_TOKENS_CHAIN1_ADDRESS"
cd testing-infra/test-tokens
aptos move publish --profile test-tokens-chain1 --named-addresses test_tokens=$TEST_TOKENS_CHAIN1_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ USDxyz deployment successful on Chain 1!"
    log_and_echo "✅ USDxyz test token deployed on hub chain"
else
    log_and_echo "   ❌ USDxyz deployment failed on Chain 1!"
    exit 1
fi

cd "$PROJECT_ROOT"

# Export USDxyz address for other scripts
echo "TEST_TOKENS_CHAIN1_ADDRESS=$TEST_TOKENS_CHAIN1_ADDRESS" >> "$PROJECT_ROOT/tmp/chain-info.env"
log "   ✅ USDxyz address saved: $TEST_TOKENS_CHAIN1_ADDRESS"

# Mint USDxyz to Alice and Bob
log ""
log "💵 Minting USDxyz to Alice and Bob on Chain 1..."

ALICE_CHAIN1_ADDRESS=$(get_profile_address "alice-chain1")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")
USDXYZ_MINT_AMOUNT="100000000000"  # 1000 USDxyz (8 decimals)

log "   - Minting $USDXYZ_MINT_AMOUNT USDxyz to Alice ($ALICE_CHAIN1_ADDRESS)..."
aptos move run --profile test-tokens-chain1 --assume-yes \
    --function-id ${TEST_TOKENS_CHAIN1_ADDRESS}::usdxyz::mint \
    --args address:$ALICE_CHAIN1_ADDRESS u64:$USDXYZ_MINT_AMOUNT >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Minted USDxyz to Alice"
else
    log_and_echo "   ❌ Failed to mint USDxyz to Alice"
    exit 1
fi

log "   - Minting $USDXYZ_MINT_AMOUNT USDxyz to Bob ($BOB_CHAIN1_ADDRESS)..."
aptos move run --profile test-tokens-chain1 --assume-yes \
    --function-id ${TEST_TOKENS_CHAIN1_ADDRESS}::usdxyz::mint \
    --args address:$BOB_CHAIN1_ADDRESS u64:$USDXYZ_MINT_AMOUNT >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Minted USDxyz to Bob"
else
    log_and_echo "   ❌ Failed to mint USDxyz to Bob"
    exit 1
fi

log_and_echo "✅ USDxyz minted to Alice and Bob on hub chain (1000 USDxyz each)"

# Display balances (APT + USDxyz)
display_balances_hub "$TEST_TOKENS_CHAIN1_ADDRESS"

log ""
log "🎉 HUB CHAIN DEPLOYMENT COMPLETE!"
log "=================================="
log "✨ Deployment script completed!"

