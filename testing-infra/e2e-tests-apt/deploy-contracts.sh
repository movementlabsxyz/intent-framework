#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "deploy-contracts"
cd "$PROJECT_ROOT"

log "🚀 DEPLOY CONTRACTS"
log "============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

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
log "✨ Deployment script completed!"

