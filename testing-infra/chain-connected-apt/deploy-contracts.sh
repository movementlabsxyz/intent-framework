#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

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
aptos config delete-profile --profile intent-account-chain2 >> "$LOG_FILE" 2>&1 || true

# Configure Chain 2 (port 8082)
log "   - Configuring Chain 2 (port 8082)..."
printf "\n" | aptos init --profile intent-account-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes >> "$LOG_FILE" 2>&1

log ""
log "📦 Deploying contracts to Chain 2..."
log "   - Getting account address for Chain 2..."
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

log "   - Deploying to Chain 2 with address: $CHAIN2_ADDRESS"
cd move-intent-framework
aptos move publish --dev --profile intent-account-chain2 --named-addresses aptos_intent=$CHAIN2_ADDRESS --assume-yes >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "   ✅ Chain 2 deployment successful!"
    log_and_echo "✅ Connected chain contracts deployed"
else
    log_and_echo "   ❌ Chain 2 deployment failed!"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

cd ..

log ""
log "🎉 CONNECTED CHAIN DEPLOYMENT COMPLETE!"
log "========================================"
log "✨ Deployment script completed!"

