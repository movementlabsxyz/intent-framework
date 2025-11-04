#!/bin/bash

# E2E Integration Test Runner (Mixed-Chain: Aptos Hub + EVM Escrow)
# 
# This script runs the mixed-chain E2E flow:
# - Chain 1 (Aptos Hub): Intent creation and fulfillment
# - Chain 3 (EVM): Escrow operations
# - Verifier: Monitors Chain 1 and releases escrow on Chain 3

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "run-tests-evm"
cd "$PROJECT_ROOT"

log_and_echo "🧪 MIXED-CHAIN E2E Integration Tests Runner"
log_and_echo "=========================================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log_and_echo ""

log_and_echo "🧹 Cleaning up any existing chains and processes..."
log_and_echo "=================================================="

# Stop EVM chain (Hardhat node)
log_and_echo "   - Stopping EVM chain..."
./testing-infra/connected-chain-evm/stop-evm-chain.sh

# Stop Aptos chains
log_and_echo "   - Stopping Aptos chains..."
./testing-infra/connected-chain-apt/stop-dual-chains.sh

# Stop any existing verifier processes
log "   - Stopping any existing verifier processes..."
pkill -f "trusted-verifier" || true

log_and_echo "✅ Cleanup complete"
log_and_echo ""

log_and_echo "🚀 Step 0: Setting up chains and deploying contracts..."
log_and_echo "======================================================"

# Setup EVM chain first
log_and_echo "📦 Setting up EVM chain..."
./testing-infra/e2e-tests-evm/setup-and-deploy-evm.sh

if [ $? -ne 0 ]; then
    log_and_echo "❌ Failed to setup EVM chain"
    exit 1
fi

log_and_echo ""
log_and_echo "📦 Setting up Aptos chains..."
./testing-infra/e2e-tests-apt/setup-and-deploy.sh

if [ $? -ne 0 ]; then
    log_and_echo "❌ Failed to setup Aptos chains"
    exit 1
fi

log_and_echo ""
log_and_echo "✅ Setup complete! Extracting module addresses..."
log_and_echo ""

# Extract deployed addresses from aptos profiles and update verifier.toml
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')

if [ -z "$CHAIN1_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract Chain 1 deployed module address"
    exit 1
fi

log_and_echo "   Chain 1 deployer: $CHAIN1_ADDRESS"

# Get EVM vault address
cd evm-intent-framework
VAULT_ADDRESS=$(grep -i "IntentVault deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-vault"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
cd ..

if [ -z "$VAULT_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not extract EVM vault address"
    exit 1
fi

log_and_echo "   EVM Vault: $VAULT_ADDRESS"

# Use verifier_testing.toml for tests - required, panic if not found
VERIFIER_TESTING_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

# Get verifier Ethereum address from config (derived from ECDSA public key)
log "   - Computing verifier Ethereum address from config..."
VERIFIER_ADDRESS=$(cd "$PROJECT_ROOT/trusted-verifier" && VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG" cargo run --bin get_verifier_eth_address 2>/dev/null | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')

if [ -z "$VERIFIER_ADDRESS" ]; then
    log_and_echo "   ⚠️  Warning: Could not compute verifier Ethereum address from config"
    log_and_echo "   Falling back to Hardhat account 1 (Bob)"
    # Get Hardhat account 1 as fallback
    cd evm-intent-framework
    VERIFIER_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')
    cd ..
    
    if [ -z "$VERIFIER_ADDRESS" ]; then
        VERIFIER_ADDRESS="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"  # Hardhat default account 1
    fi
fi

log_and_echo "   EVM Verifier: $VERIFIER_ADDRESS"

# Export config path for Rust code to use (absolute path so tests can find it)
export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

# Update module addresses in verifier_testing.toml
sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Add or update EVM chain section in verifier_testing.toml
if grep -q "^\[evm_chain\]" "$VERIFIER_TESTING_CONFIG"; then
    # Update existing section
    sed -i "/\[evm_chain\]/,/^\[/ s|rpc_url = .*|rpc_url = \"http://127.0.0.1:8545\"|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[evm_chain\]/,/^\[/ s|vault_address = .*|vault_address = \"$VAULT_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[evm_chain\]/,/^\[/ s|chain_id = .*|chain_id = 31337|" "$VERIFIER_TESTING_CONFIG"
    sed -i "/\[evm_chain\]/,/^\[/ s|verifier_address = .*|verifier_address = \"$VERIFIER_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
else
    # Add new section before [verifier] section
    if grep -q "^\[verifier\]" "$VERIFIER_TESTING_CONFIG"; then
        sed -i "/^\[verifier\]/i [evm_chain]\nrpc_url = \"http://127.0.0.1:8545\"\nvault_address = \"$VAULT_ADDRESS\"\nchain_id = 31337\nverifier_address = \"$VERIFIER_ADDRESS\"\n" "$VERIFIER_TESTING_CONFIG"
    else
        # Append at end of file
        echo "" >> "$VERIFIER_TESTING_CONFIG"
        echo "[evm_chain]" >> "$VERIFIER_TESTING_CONFIG"
        echo "rpc_url = \"http://127.0.0.1:8545\"" >> "$VERIFIER_TESTING_CONFIG"
        echo "vault_address = \"$VAULT_ADDRESS\"" >> "$VERIFIER_TESTING_CONFIG"
        echo "chain_id = 31337" >> "$VERIFIER_TESTING_CONFIG"
        echo "verifier_address = \"$VERIFIER_ADDRESS\"" >> "$VERIFIER_TESTING_CONFIG"
    fi
fi

# Get Alice and Bob addresses and update known_accounts
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')

if [ -n "$ALICE_CHAIN1_ADDRESS" ] && [ -n "$BOB_CHAIN1_ADDRESS" ]; then
    sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

log_and_echo "✅ Updated verifier_testing.toml with deployed addresses"
log_and_echo ""

log_and_echo "📝 Step 1: Submitting mixed-chain intents..."
log_and_echo "==========================================="
./testing-infra/e2e-tests-evm/submit-cross-chain-intent-evm.sh 0

if [ $? -ne 0 ]; then
    log_and_echo "❌ Failed to submit intents"
    exit 1
fi

log_and_echo ""
log_and_echo "✅ Intents submitted successfully!"
log_and_echo ""
display_balances
log_and_echo ""

log_and_echo "🚀 Step 2: Running verifier service to monitor and release escrow..."
log_and_echo "================================================================"
log_and_echo "   The verifier will:"
log_and_echo "   1. Monitor Chain 1 (Aptos hub) for intents and fulfillments"
log_and_echo "   2. When fulfillment detected, create ECDSA signature"
log_and_echo "   3. Release escrow on Chain 3 (EVM)"
log_and_echo ""

# Check if verifier is already running and stop it
log_and_echo "   Checking for existing verifiers..."
# Look for the actual cargo/rust processes, not the script
if pgrep -f "cargo.*trusted-verifier" > /dev/null || pgrep -f "target/debug/trusted-verifier" > /dev/null; then
    log_and_echo "   ⚠️  Found existing verifier processes, stopping them..."
    pkill -f "cargo.*trusted-verifier"
    pkill -f "target/debug/trusted-verifier"
    sleep 2
else
    log_and_echo "   ✅ No existing verifier processes"
fi

# Start verifier in background
cd trusted-verifier
VERIFIER_PID=""
VERIFIER_LOG="$PROJECT_ROOT/tmp/intent-framework-logs/verifier-evm.log"
mkdir -p "$(dirname "$VERIFIER_LOG")"

log_and_echo "   Starting verifier service..."
cargo run --bin trusted-verifier > "$VERIFIER_LOG" 2>&1 &
VERIFIER_PID=$!

# Wait for verifier to start
sleep 5

if ! ps -p "$VERIFIER_PID" > /dev/null 2>&1; then
    log_and_echo "   ❌ Verifier failed to start"
    cat "$VERIFIER_LOG"
    exit 1
fi

log_and_echo "   ✅ Verifier started (PID: $VERIFIER_PID)"
log_and_echo ""

cd ..

# Give verifier some time to process events
log_and_echo "   ⏳ Waiting for verifier to process events (30 seconds)..."
sleep 30

# Check verifier health
if curl -s http://127.0.0.1:3333/health >/dev/null 2>&1; then
    log_and_echo "   ✅ Verifier is healthy"
else
    log_and_echo "   ⚠️  Verifier health check failed"
fi

log_and_echo ""
log_and_echo "🔓 Step 3: Releasing EVM escrow..."
log_and_echo "=================================="
./testing-infra/e2e-tests-evm/release-evm-escrow.sh

log_and_echo ""
display_balances
log_and_echo ""
log_and_echo "✅ E2E test flow completed!"
log_and_echo ""

# Stop verifier
if [ -n "$VERIFIER_PID" ] && ps -p "$VERIFIER_PID" > /dev/null 2>&1; then
    log_and_echo "   Stopping verifier..."
    kill "$VERIFIER_PID" 2>/dev/null || true
    wait "$VERIFIER_PID" 2>/dev/null || true
    log_and_echo "   ✅ Verifier stopped"
fi

log_and_echo ""
log_and_echo "🧹 Step 4: Cleaning up chains..."
log_and_echo "================================"
./testing-infra/connected-chain-evm/stop-evm-chain.sh
./testing-infra/connected-chain-apt/stop-dual-chains.sh

log_and_echo ""
log_and_echo "✅ All E2E tests completed!"
