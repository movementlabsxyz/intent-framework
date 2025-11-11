#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_apt.sh"

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
    log_and_echo "   See log file for details: $LOG_FILE or set LOG function to echo as well"
    exit 1
fi

cd ..

log ""
log "🎉 HUB CHAIN DEPLOYMENT COMPLETE!"
log "=================================="
log "✨ Deployment script completed!"

