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

log_and_echo "🧹 Step -1: Cleaning up any existing chains and processes..."
log_and_echo "=========================================================="
./testing-infra/connected-chain-apt/stop-dual-chains.sh
./testing-infra/connected-chain-evm/stop-evm-chain.sh
pkill -f "trusted-verifier" || true
log_and_echo "✅ Cleanup complete"
log_and_echo ""

log_and_echo "🚀 Step 0: Setting up chains and deploying contracts..."
log_and_echo "======================================================"

./testing-infra/e2e-tests-evm/setup-and-deploy-evm.sh

./testing-infra/connected-chain-apt/setup-dual-chains.sh
./testing-infra/connected-chain-apt/setup-alice-bob.sh
./testing-infra/e2e-tests-apt/deploy-contracts.sh

echo ""
echo "🚀 Step 3: Submitting mixed-chain intents, configuring verifier..."
echo "==============================================================="
./testing-infra/e2e-tests-evm/submit-cross-chain-intent-evm.sh 0
./testing-infra/e2e-tests-evm/configure-verifier.sh

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
