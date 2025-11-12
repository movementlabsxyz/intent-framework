#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_apt.sh"

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
    cat "$LOG_FILE"
    exit 1
fi

cd ..

# Initialize solver registry (idempotent - will fail silently if already initialized)
log ""
log "🔧 Initializing solver registry..."
initialize_solver_registry "intent-account-chain2" "$CHAIN2_ADDRESS" "$LOG_FILE"

log ""
log "🎉 CONNECTED CHAIN DEPLOYMENT COMPLETE!"
log "========================================"
log "✨ Deployment script completed!"

