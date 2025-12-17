#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "deploy-contracts-connected"
cd "$PROJECT_ROOT"

log "🚀 DEPLOY CONTRACTS - CONNECTED CHAIN (Chain 2)"
log "================================================"
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "⚙️  Configuring Aptos CLI for Chain 2..."

# Clean up any existing profile to ensure fresh address each run
log "🧹 Cleaning up existing CLI profile..."
cleanup_aptos_profile "intent-account-chain2" "$LOG_FILE"

# Configure Chain 2 (port 8082)
log "   - Configuring Chain 2 (port 8082)..."
init_aptos_profile "intent-account-chain2" "2" "$LOG_FILE"

log ""
log "📦 Deploying contracts to Chain 2..."
log "   - Getting account address for Chain 2..."
CHAIN2_ADDRESS=$(get_profile_address "intent-account-chain2")

log "   - Deploying to Chain 2 with address: $CHAIN2_ADDRESS"
cd move-intent-framework
aptos move publish --dev --profile intent-account-chain2 --named-addresses mvmt_intent=$CHAIN2_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Chain 2 deployment successful!"
    log_and_echo "✅ Connected chain contracts deployed"
else
    log_and_echo "   ❌ Chain 2 deployment failed!"
    log_and_echo "   Log file contents:"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    cat "$LOG_FILE"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
fi

cd ..

# Initialize fa_intent chain info (required for cross-chain intent detection)
log ""
log "🔧 Initializing fa_intent chain info (chain_id=2)..."
aptos move run --profile intent-account-chain2 --assume-yes \
    --function-id ${CHAIN2_ADDRESS}::fa_intent::initialize \
    --args u64:2 >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ fa_intent chain info initialized (chain_id=2)"
else
    log "   ⚠️  fa_intent chain info may already be initialized (ignoring)"
fi

# Initialize solver registry (idempotent - will fail silently if already initialized)
log ""
log "🔧 Initializing solver registry..."
initialize_solver_registry "intent-account-chain2" "$CHAIN2_ADDRESS" "$LOG_FILE"

# Deploy USDxyz test token
log ""
log "💵 Deploying USDxyz test token to Chain 2..."

TEST_TOKENS_CHAIN2_ADDRESS=$(get_profile_address "test-tokens-chain2")

log "   - Deploying USDxyz with address: $TEST_TOKENS_CHAIN2_ADDRESS"
cd testing-infra/ci-e2e/test-tokens
aptos move publish --profile test-tokens-chain2 --named-addresses test_tokens=$TEST_TOKENS_CHAIN2_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ USDxyz deployment successful on Chain 2!"
    log_and_echo "✅ USDxyz test token deployed on connected chain"
else
    log_and_echo "   ❌ USDxyz deployment failed on Chain 2!"
    exit 1
fi

cd "$PROJECT_ROOT"

# Export USDxyz address for other scripts
echo "TEST_TOKENS_CHAIN2_ADDRESS=$TEST_TOKENS_CHAIN2_ADDRESS" >> "$PROJECT_ROOT/.tmp/chain-info.env"
log "   ✅ USDxyz address saved: $TEST_TOKENS_CHAIN2_ADDRESS"

# Mint USDxyz to Requester and Solver
log ""
log "💵 Minting USDxyz to Requester and Solver on Chain 2..."

REQUESTER_CHAIN2_ADDRESS=$(get_profile_address "requester-chain2")
SOLVER_CHAIN2_ADDRESS=$(get_profile_address "solver-chain2")
USDXYZ_MINT_AMOUNT="1000000"  # 1 USDxyz (6 decimals = 1_000_000)

log "   - Minting $USDXYZ_MINT_AMOUNT USDxyz to Requester ($REQUESTER_CHAIN2_ADDRESS)..."
aptos move run --profile test-tokens-chain2 --assume-yes \
    --function-id ${TEST_TOKENS_CHAIN2_ADDRESS}::usdxyz::mint \
    --args address:$REQUESTER_CHAIN2_ADDRESS u64:$USDXYZ_MINT_AMOUNT >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Minted USDxyz to Requester"
else
    log_and_echo "   ❌ Failed to mint USDxyz to Requester"
    exit 1
fi

log "   - Minting $USDXYZ_MINT_AMOUNT USDxyz to Solver ($SOLVER_CHAIN2_ADDRESS)..."
aptos move run --profile test-tokens-chain2 --assume-yes \
    --function-id ${TEST_TOKENS_CHAIN2_ADDRESS}::usdxyz::mint \
    --args address:$SOLVER_CHAIN2_ADDRESS u64:$USDXYZ_MINT_AMOUNT >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Minted USDxyz to Solver"
else
    log_and_echo "   ❌ Failed to mint USDxyz to Solver"
    exit 1
fi

log_and_echo "✅ USDxyz minted to Requester and Solver on connected chain (1 USDxyz each)"

# Assert balances are correct after minting
assert_usdxyz_balance "requester-chain2" "2" "$TEST_TOKENS_CHAIN2_ADDRESS" "1000000" "post-mint-requester"
assert_usdxyz_balance "solver-chain2" "2" "$TEST_TOKENS_CHAIN2_ADDRESS" "1000000" "post-mint-solver"

# Display balances (APT + USDxyz)
display_balances_connected_mvm "$TEST_TOKENS_CHAIN2_ADDRESS"

log ""
log "🎉 CONNECTED CHAIN DEPLOYMENT COMPLETE!"
log "========================================"
log "✨ Deployment script completed!"

