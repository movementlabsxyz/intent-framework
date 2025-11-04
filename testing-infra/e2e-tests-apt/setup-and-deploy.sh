#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-and-deploy"
cd "$PROJECT_ROOT"

log "🚀 APTOS INTENT FRAMEWORK - SETUP AND DEPLOY"
log "============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "🔗 Step 1: Setting up dual Docker chains with Alice and Bob accounts..."
log " ============================================="
./testing-infra/connected-chain-apt/setup-dual-chains-and-test-alice-bob.sh

if [ $? -ne 0 ]; then
    log_and_echo "❌ Failed to setup dual chains with Alice and Bob accounts"
    exit 1
fi

log ""
log "⚙️  Step 2: Configuring Aptos CLI for both chains..."
log " ============================================="

# Clean up any existing profiles to ensure fresh addresses each run
log "🧹 Cleaning up existing CLI profiles..."
aptos config delete-profile --profile intent-account-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile intent-account-chain2 >> "$LOG_FILE" 2>&1 || true

# Configure Chain 1 (port 8080)
log "   - Configuring Chain 1 (port 8080)..."
printf "\n" | aptos init --profile intent-account-chain1 --network local --assume-yes >> "$LOG_FILE" 2>&1

# Configure Chain 2 (port 8082)
log "   - Configuring Chain 2 (port 8082)..."
printf "\n" | aptos init --profile intent-account-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes >> "$LOG_FILE" 2>&1

log ""
log "📦 Step 3: Deploying contracts to Chain 1..."
log "   - Getting account address for Chain 1..."
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')

log "   - Deploying to Chain 1 with address: $CHAIN1_ADDRESS"
cd move-intent-framework
aptos move publish --dev --profile intent-account-chain1 --named-addresses aptos_intent=$CHAIN1_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Chain 1 deployment successful!"
else
    log_and_echo "   ❌ Chain 1 deployment failed!"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

log ""
log "📦 Step 4: Deploying contracts to Chain 2..."
log "   - Getting account address for Chain 2..."
cd ..
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

log "   - Deploying to Chain 2 with address: $CHAIN2_ADDRESS"
cd move-intent-framework
aptos move publish --dev --profile intent-account-chain2 --named-addresses aptos_intent=$CHAIN2_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Chain 2 deployment successful!"
else
    log_and_echo "   ❌ Chain 2 deployment failed!"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

log_and_echo "✅ Contracts deployed"

log ""
log "🎉 DEPLOYMENT COMPLETE!"
log "======================="
log "Chain 1 (intent-account-chain1):"
log "   REST API: http://127.0.0.1:8080/v1"
log "   Faucet:   http://127.0.0.1:8081"
log "   Account:  $CHAIN1_ADDRESS"
log "   Contract: 0x${CHAIN1_ADDRESS}::aptos_intent"
log ""
log "Chain 2 (intent-account-chain2):"
log "   REST API: http://127.0.0.1:8082/v1"
log "   Faucet:   http://127.0.0.1:8083"
log "   Account:  $CHAIN2_ADDRESS"
log "   Contract: 0x${CHAIN2_ADDRESS}::aptos_intent"
log ""
log "📝 NOTE: The 'Account' is the deployer address, 'Contract' is the actual contract address"
log "   Use the Contract address to call contract functions!"
log ""
log "📡 API Examples:"
log "   Check Chain 1 status:    curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height'"
log "   Check Chain 2 status:    curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height'"
log "   Get Chain 1 account:     curl -s http://127.0.0.1:8080/v1/accounts/$CHAIN1_ADDRESS"
log "   Get Chain 2 account:     curl -s http://127.0.0.1:8082/v1/accounts/$CHAIN2_ADDRESS"
log "   Fund Chain 1 account:   curl -X POST \"http://127.0.0.1:8081/mint?address=<ADDRESS>&amount=100000000\""
log "   Fund Chain 2 account:   curl -X POST \"http://127.0.0.1:8083/mint?address=<ADDRESS>&amount=100000000\""
log ""
log "📋 Useful commands:"
log "   Stop chains:     ./testing-infra/connected-chain-apt/stop-dual-chains.sh"
log "   View Chain 1:    aptos config show-profiles --profile intent-account-chain1"
log "   View Chain 2:    aptos config show-profiles --profile intent-account-chain2"

log ""
log "✨ Setup and deployment script completed!"
