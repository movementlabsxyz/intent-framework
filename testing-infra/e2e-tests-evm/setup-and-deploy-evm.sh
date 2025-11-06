#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-and-deploy-evm"
cd "$PROJECT_ROOT"

log "🚀 EVM CHAIN - DEPLOY"
log "===================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "📦 Step 1: Deploying IntentVault to EVM chain..."
log "============================================="
./testing-infra/e2e-tests-evm/deploy-vault.sh

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

# Get verifier address (Hardhat account 0 - Deployer is the verifier)
# Hardhat default accounts: Account 0 = Deployer/Verifier, Account 1 = Alice, Account 2 = Bob
VERIFIER_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
log "   ✅ Verifier address: $VERIFIER_ADDRESS (Account 0)"

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
