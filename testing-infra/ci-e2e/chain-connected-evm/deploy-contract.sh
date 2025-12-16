#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_evm.sh"
source "$SCRIPT_DIR/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "deploy-contract"
cd "$PROJECT_ROOT"

log "🚀 EVM CHAIN - DEPLOY"
log "===================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "📦 Deploying IntentEscrow to EVM chain..."
log "============================================="

# Check if Hardhat node is running
if ! check_evm_chain_running; then
    log_and_echo "❌ Hardhat node is not running. Please run testing-infra/ci-e2e/chain-connected-evm/setup-chain.sh first"
    exit 1
fi

log ""
log "🔑 Configuration:"
log "   Computing verifier Ethereum address from config..."

# Setup verifier config (always generates fresh ephemeral keys for CI/E2E testing)
setup_verifier_config

# Get verifier Ethereum address from config (derived from ECDSA public key)
VERIFIER_DIR="$PROJECT_ROOT/trusted-verifier"
CONFIG_PATH="$VERIFIER_CONFIG_PATH"

VERIFIER_ETH_OUTPUT=$(cd "$PROJECT_ROOT" && env HOME="${HOME}" VERIFIER_CONFIG_PATH="$CONFIG_PATH" nix develop -c bash -c "cd trusted-verifier && cargo run --bin get_verifier_eth_address 2>&1" | tee -a "$LOG_FILE")
VERIFIER_ETH_ADDRESS=$(echo "$VERIFIER_ETH_OUTPUT" | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')

if [ -z "$VERIFIER_ETH_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not compute verifier Ethereum address from config"
    log_and_echo "   Command output:"
    echo "$VERIFIER_ETH_OUTPUT"
    log_and_echo "   Check that trusted-verifier/config/verifier-e2e-ci-testing.toml has valid keys"
    exit 1
fi

log "   ✅ Verifier Ethereum address: $VERIFIER_ETH_ADDRESS"
log "   RPC URL: http://127.0.0.1:8545"

# Deploy escrow contract (run in nix develop)
log ""
log "📤 Deploying IntentEscrow..."
DEPLOY_OUTPUT=$(run_hardhat_command "npx hardhat run scripts/deploy.js --network localhost" "VERIFIER_ADDRESS='$VERIFIER_ETH_ADDRESS'" 2>&1 | tee -a "$LOG_FILE")

# Extract contract address from output
CONTRACT_ADDRESS=$(extract_escrow_contract_address "$DEPLOY_OUTPUT")

log ""
log "✅ IntentEscrow deployed successfully!"
log "   Contract Address: $CONTRACT_ADDRESS"
log ""
log "📋 Contract Details:"
log "   Network:      localhost"
log "   RPC URL:      http://127.0.0.1:8545"
log "   Chain ID:     31337 (Hardhat default)"
log ""
log "🔍 Verify deployment:"
log "   npx hardhat verify --network localhost $CONTRACT_ADDRESS <verifier_address>"

log ""
log "✅ IntentEscrow deployed"

# Deploy USDxyz token
log ""
log "💵 Deploying USDxyz token to EVM chain..."

USDXYZ_OUTPUT=$(run_hardhat_command "npx hardhat run test-scripts/deploy-usdxyz.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
USDXYZ_ADDRESS=$(echo "$USDXYZ_OUTPUT" | grep "USDxyz deployed to:" | awk '{print $NF}' | tr -d '\n')

if [ -z "$USDXYZ_ADDRESS" ]; then
    log_and_echo "❌ USDxyz deployment failed!"
    exit 1
fi

log "   ✅ USDxyz deployed to: $USDXYZ_ADDRESS"

# Save escrow and USDxyz addresses for other scripts
echo "ESCROW_CONTRACT_ADDRESS=$CONTRACT_ADDRESS" >> "$PROJECT_ROOT/.tmp/chain-info.env"
echo "USDXYZ_EVM_ADDRESS=$USDXYZ_ADDRESS" >> "$PROJECT_ROOT/.tmp/chain-info.env"

# Mint USDxyz to Requester and Solver (accounts 1 and 2)
log ""
log "💵 Minting USDxyz to Requester and Solver on EVM chain..."

REQUESTER_EVM_ADDRESS=$(get_hardhat_account_address "1")
SOLVER_EVM_ADDRESS=$(get_hardhat_account_address "2")
USDXYZ_MINT_AMOUNT="1000000"  # 1 USDxyz (6 decimals = 1_000_000)

log "   - Minting USDxyz to Requester ($REQUESTER_EVM_ADDRESS)..."
MINT_OUTPUT=$(run_hardhat_command "npx hardhat run scripts/mint-token.js --network localhost" "TOKEN_ADDRESS='$USDXYZ_ADDRESS' RECIPIENT='$REQUESTER_EVM_ADDRESS' AMOUNT='$USDXYZ_MINT_AMOUNT'" 2>&1 | tee -a "$LOG_FILE")
if echo "$MINT_OUTPUT" | grep -q "SUCCESS"; then
    log "   ✅ Minted USDxyz to Requester"
else
    log_and_echo "   ❌ Failed to mint USDxyz to Requester"
    exit 1
fi

log "   - Minting USDxyz to Solver ($SOLVER_EVM_ADDRESS)..."
MINT_OUTPUT=$(run_hardhat_command "npx hardhat run scripts/mint-token.js --network localhost" "TOKEN_ADDRESS='$USDXYZ_ADDRESS' RECIPIENT='$SOLVER_EVM_ADDRESS' AMOUNT='$USDXYZ_MINT_AMOUNT'" 2>&1 | tee -a "$LOG_FILE")
if echo "$MINT_OUTPUT" | grep -q "SUCCESS"; then
    log "   ✅ Minted USDxyz to Solver"
else
    log_and_echo "   ❌ Failed to mint USDxyz to Solver"
    exit 1
fi

log_and_echo "✅ USDxyz minted to Requester and Solver on EVM chain"

# Display balances (ETH + USDxyz)
display_balances_connected_evm "$USDXYZ_ADDRESS"

log ""
log "🎉 EVM DEPLOYMENT COMPLETE!"
log "==========================="
log "EVM Chain:"
log "   RPC URL:  http://127.0.0.1:8545"
log "   Chain ID: 31337"
log "   IntentEscrow: $CONTRACT_ADDRESS"
log "   USDxyz Token: $USDXYZ_ADDRESS"
log "   Verifier: $VERIFIER_ETH_ADDRESS"
log ""
log "📡 API Examples:"
log "   Check EVM Chain:    curl -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
log ""
log "📋 Useful commands:"
log "   Stop EVM chain:  ./testing-infra/ci-e2e/chain-connected-evm/stop-chain.sh"
log ""
log "✨ EVM deployment script completed!"

