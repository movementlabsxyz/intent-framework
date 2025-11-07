#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "deploy-contract"
cd "$PROJECT_ROOT"

log "🚀 EVM CHAIN - DEPLOY"
log "===================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "📦 Deploying IntentVault to EVM chain..."
log "============================================="

# Check if Hardhat node is running
if ! check_evm_chain_running; then
    log_and_echo "❌ Hardhat node is not running. Please run testing-infra/chain-connected-evm/setup-chain.sh first"
    exit 1
fi

log ""
log "🔑 Configuration:"
log "   Computing verifier Ethereum address from config..."

# Get verifier Ethereum address from config (derived from ECDSA public key)
VERIFIER_DIR="$PROJECT_ROOT/trusted-verifier"
CONFIG_PATH="$PROJECT_ROOT/trusted-verifier/config/verifier_testing.toml"

# Check if config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $CONFIG_PATH"
    log_and_echo "   The verifier config file is required for deployment"
    exit 1
fi

VERIFIER_ETH_ADDRESS=$(cd "$VERIFIER_DIR" && VERIFIER_CONFIG_PATH="$CONFIG_PATH" cargo run --bin get_verifier_eth_address 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')

if [ -z "$VERIFIER_ETH_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not compute verifier Ethereum address from config"
    log_and_echo "   Check that trusted-verifier/config/verifier_testing.toml has valid keys"
    log_and_echo "   Run: cargo run --bin get_verifier_eth_address in trusted-verifier directory"
    exit 1
fi

log "   ✅ Verifier Ethereum address: $VERIFIER_ETH_ADDRESS"
log "   RPC URL: http://127.0.0.1:8545"

# Deploy vault contract (run in nix develop)
log ""
log "📤 Deploying IntentVault..."
DEPLOY_OUTPUT=$(run_hardhat_command "npx hardhat run scripts/deploy.js --network localhost" "VERIFIER_ADDRESS='$VERIFIER_ETH_ADDRESS'" 2>&1 | tee -a "$LOG_FILE")

# Extract contract address from output
VAULT_ADDRESS=$(extract_vault_address "$DEPLOY_OUTPUT")

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

log ""
log "✅ EVM contracts deployed"
log ""
log "🎉 EVM DEPLOYMENT COMPLETE!"
log "==========================="
log "EVM Chain:"
log "   RPC URL:  http://127.0.0.1:8545"
log "   Chain ID: 31337"
log "   Vault:    $VAULT_ADDRESS"
log "   Verifier: $VERIFIER_ETH_ADDRESS"
log ""
log "📡 API Examples:"
log "   Check EVM Chain:    curl -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
log ""
log "📋 Useful commands:"
log "   Stop EVM chain:  ./testing-infra/chain-connected-evm/stop-chain.sh"
log ""
log "✨ EVM deployment script completed!"

