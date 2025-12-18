#!/bin/bash

# E2E Integration Test Runner - OUTFLOW (EVM)
# 
# This script runs the outflow E2E tests with EVM connected chain.
# It sets up chains, deploys contracts, starts verifier for negotiation routing,
# submits outflow intents via verifier, then runs the tests.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root and logging
setup_project_root
setup_logging "run-tests-evm-outflow"
cd "$PROJECT_ROOT"

log_and_echo "🧪 E2E Test for Connected EVM Chain - OUTFLOW"
log_and_echo "=============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log_and_echo ""

log_and_echo "🧹 Step 1: Cleaning up any existing chains, accounts and processes..."
log_and_echo "=========================================================="
./testing-infra/ci-e2e/chain-connected-evm/cleanup.sh

log_and_echo ""
log_and_echo "🔨 Step 2: Building Rust services (verifier and solver)..."
log_and_echo "==========================================================="
pushd "$PROJECT_ROOT/trusted-verifier" > /dev/null
cargo build --bin trusted-verifier 2>&1 | tail -5
popd > /dev/null
log_and_echo "   ✅ Verifier built"

pushd "$PROJECT_ROOT/solver" > /dev/null
cargo build --bin solver 2>&1 | tail -5
popd > /dev/null
log_and_echo "   ✅ Solver built"
log_and_echo ""

log_and_echo "🚀 Step 3: Setting up chains and deploying contracts..."
log_and_echo "======================================================"
./testing-infra/ci-e2e/chain-connected-evm/setup-chain.sh
./testing-infra/ci-e2e/chain-connected-evm/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-connected-evm/deploy-contract.sh
./testing-infra/ci-e2e/chain-hub/setup-chain.sh
./testing-infra/ci-e2e/chain-hub/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-hub/deploy-contracts.sh

log_and_echo ""
log_and_echo "🚀 Step 4: Configuring and starting verifier (for negotiation routing)..."
log_and_echo "=========================================================================="
./testing-infra/ci-e2e/e2e-tests-evm/start-verifier.sh

# Start solver service for automatic signing and fulfillment
log_and_echo ""
log_and_echo "🚀 Step 4b: Starting solver service..."
log_and_echo "======================================="
./testing-infra/ci-e2e/e2e-tests-evm/start-solver.sh

# Verify solver started successfully
./testing-infra/ci-e2e/verify-solver-running.sh

log_and_echo ""
log_and_echo "🚀 Step 5: Testing OUTFLOW intents (hub chain → connected EVM chain)..."
log_and_echo "====================================================================="
log_and_echo "   Submitting outflow cross-chain intents via verifier negotiation routing..."
log_and_echo ""
log_and_echo "💰 Pre-Intent Balance Validation"
log_and_echo "=========================================="
log_and_echo "   Everybody starts with 1 USDxyz on their origin chain before outflow"
./testing-infra/ci-e2e/e2e-tests-evm/balance-check.sh 1000000 1000000 1000000 1000000

./testing-infra/ci-e2e/e2e-tests-evm/outflow-submit-hub-intent.sh

# Load intent ID for solver fulfillment wait
if ! load_intent_info "INTENT_ID"; then
    log_and_echo "❌ ERROR: Failed to load intent info"
    exit 1
fi

log_and_echo ""
log_and_echo "🤖 Step 5b: Waiting for solver to automatically fulfill..."
log_and_echo "==========================================================="
log_and_echo "   The solver service is running and will:"
log_and_echo "   1. Detect the intent on hub chain"
log_and_echo "   2. Transfer tokens to requester on connected EVM chain"
log_and_echo "   3. Call verifier to validate and get approval signature"
log_and_echo "   4. Fulfill the hub intent with approval"
log_and_echo ""

if ! wait_for_solver_fulfillment "$INTENT_ID" "outflow" 60; then
    log_and_echo "❌ ERROR: Solver did not fulfill the intent automatically"
    display_service_logs "Solver fulfillment timeout"
    exit 1
fi

log_and_echo "✅ Solver fulfilled the intent automatically!"

log_and_echo ""
log_and_echo "💰 Final Balance View"
log_and_echo "=========================================="
# Outflow: Solver gets from hub intent (2000000 on hub, 0 on EVM transferred to requester)
#          Requester receives on EVM (0 on hub locked in intent, 2000000 on EVM)
./testing-infra/ci-e2e/e2e-tests-evm/balance-check.sh 2000000 0 0 2000000 || true

log_and_echo ""
log_and_echo "✅ E2E outflow test completed!"
log_and_echo ""

log_and_echo "🧹 Step 6: Cleaning up chains, accounts and processes..."
log_and_echo "========================================================"
./testing-infra/ci-e2e/chain-connected-evm/cleanup.sh

