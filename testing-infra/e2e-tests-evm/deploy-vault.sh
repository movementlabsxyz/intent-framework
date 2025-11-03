#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "deploy-vault"
cd "$PROJECT_ROOT"

log "📦 Deploying IntentVault Contract"
log "=================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Check if Hardhat node is running
if ! curl -s -X POST http://127.0.0.1:8545 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    >/dev/null 2>&1; then
    log_and_echo "❌ Hardhat node is not running. Please run testing-infra/evm-chain/setup-evm-chain.sh first"
    exit 1
fi

log ""
log "🔑 Configuration:"
log "   Verifier address will be set to first Hardhat account (for testing)"
log "   RPC URL: http://127.0.0.1:8545"

cd evm-intent-framework

# Deploy vault contract (run in nix develop)
log ""
log "📤 Deploying IntentVault..."
DEPLOY_OUTPUT=$(nix develop -c bash -c "npx hardhat run scripts/deploy.js --network localhost" 2>&1 | tee -a "$LOG_FILE")

# Extract contract address from output
VAULT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -i "IntentVault deployed to" | awk '{print $NF}' | tr -d '\n')

if [ -z "$VAULT_ADDRESS" ]; then
    # Try alternative pattern
    VAULT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oE "0x[a-fA-F0-9]{40}" | head -1)
fi

if [ -z "$VAULT_ADDRESS" ]; then
    log_and_echo "❌ Failed to extract contract address from deployment"
    log_and_echo "   Deployment output:"
    echo "$DEPLOY_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

log ""
log "✅ IntentVault deployed successfully!"
log "   Contract Address: $VAULT_ADDRESS"
log ""
log "📋 Contract Details:"
log "   Network:      localhost"
log "   RPC URL:      http://127.0.0.1:8545"
log "   Chain ID:     31337 (Hardhat default)"
log ""
log "🔍 Verify deployment:"
log "   npx hardhat verify --network localhost $VAULT_ADDRESS <verifier_address>"

cd ..

