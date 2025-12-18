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

# Initialize fa_intent chain info (required for cross-chain intent detection)
log ""
log "🔧 Initializing fa_intent chain info (chain_id=1)..."
aptos move run --profile intent-account-chain1 --assume-yes \
    --function-id ${CHAIN1_ADDRESS}::fa_intent::initialize \
    --args u64:1 >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ fa_intent chain info initialized (chain_id=1)"
else
    log "   ⚠️  fa_intent chain info may already be initialized (ignoring)"
fi

# Initialize solver registry (idempotent - will fail silently if already initialized)
log ""
log "🔧 Initializing solver registry..."
initialize_solver_registry "intent-account-chain1" "$CHAIN1_ADDRESS" "$LOG_FILE"

# Deploy USDhub test token
log ""
log "💵 Deploying USDhub test token to Chain 1..."

TEST_TOKENS_CHAIN1_ADDRESS=$(get_profile_address "test-tokens-chain1")

log "   - Deploying USDhub with address: $TEST_TOKENS_CHAIN1_ADDRESS"
cd testing-infra/ci-e2e/test-tokens
aptos move publish --profile test-tokens-chain1 --named-addresses test_tokens=$TEST_TOKENS_CHAIN1_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ USDhub deployment successful on Chain 1!"
    log_and_echo "✅ USDhub test token deployed on hub chain"
else
    log_and_echo "   ❌ USDhub deployment failed on Chain 1!"
    exit 1
fi

cd "$PROJECT_ROOT"

# Export USDhub address for other scripts (cleanup deletes this file, so append is safe - creates file if it doesn't exist)
echo "TEST_TOKENS_CHAIN1_ADDRESS=$TEST_TOKENS_CHAIN1_ADDRESS" >> "$PROJECT_ROOT/.tmp/chain-info.env"
log "   ✅ USDhub address saved: $TEST_TOKENS_CHAIN1_ADDRESS"

# Mint USDhub to Requester and Solver
log ""
log "💵 Minting USDhub to Requester and Solver on Chain 1..."

REQUESTER_CHAIN1_ADDRESS=$(get_profile_address "requester-chain1")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")
USDHUB_MINT_AMOUNT="1000000"  # 1 USDhub (6 decimals = 1_000_000)

log "   - Minting $USDHUB_MINT_AMOUNT 10e-6.USDhub to Requester ($REQUESTER_CHAIN1_ADDRESS)..."
aptos move run --profile test-tokens-chain1 --assume-yes \
    --function-id ${TEST_TOKENS_CHAIN1_ADDRESS}::usdxyz::mint \
    --args address:$REQUESTER_CHAIN1_ADDRESS u64:$USDHUB_MINT_AMOUNT >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Minted USDhub to Requester"
else
    log_and_echo "   ❌ Failed to mint USDhub to Requester"
    exit 1
fi

log "   - Minting $USDHUB_MINT_AMOUNT 10e-6.USDhub to Solver ($SOLVER_CHAIN1_ADDRESS)..."
aptos move run --profile test-tokens-chain1 --assume-yes \
    --function-id ${TEST_TOKENS_CHAIN1_ADDRESS}::usdxyz::mint \
    --args address:$SOLVER_CHAIN1_ADDRESS u64:$USDHUB_MINT_AMOUNT >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Minted USDhub to Solver"
else
    log_and_echo "   ❌ Failed to mint USDhub to Solver"
    exit 1
fi

log_and_echo "✅ USDhub minted to Requester and Solver on hub chain (1 USDhub each)"

# Display balances (APT + USDhub)
display_balances_hub "$TEST_TOKENS_CHAIN1_ADDRESS"

log ""
log "🎉 HUB CHAIN DEPLOYMENT COMPLETE!"
log "=================================="
log "✨ Deployment script completed!"

