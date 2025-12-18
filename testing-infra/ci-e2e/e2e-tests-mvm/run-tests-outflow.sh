#!/bin/bash

# E2E Integration Test Runner - OUTFLOW
# 
# This script runs the outflow E2E tests that require Docker chains.
# It sets up chains, deploys contracts, starts verifier for negotiation routing,
# submits outflow intents via verifier, then runs the tests.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root
setup_project_root
cd "$PROJECT_ROOT"

echo "🧪 E2E Test with Connected Move VM Chain - OUTFLOW"
echo "=================================================="
echo ""

echo "🧹 Step 1: Cleaning up any existing chains, accounts and processes..."
echo "================================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

echo ""
echo "🔨 Step 2: Building Rust services (verifier and solver)..."
echo "==========================================================="
pushd "$PROJECT_ROOT/trusted-verifier" > /dev/null
cargo build --bin trusted-verifier 2>&1 | tail -5
popd > /dev/null
echo "   ✅ Verifier built"

pushd "$PROJECT_ROOT/solver" > /dev/null
cargo build --bin solver 2>&1 | tail -5
popd > /dev/null
echo "   ✅ Solver built"
echo ""

echo "🚀 Step 3: Setting up chains, deploying contracts, funding accounts"
echo "===================================================================="
./testing-infra/ci-e2e/chain-hub/setup-chain.sh
./testing-infra/ci-e2e/chain-hub/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-hub/deploy-contracts.sh
./testing-infra/ci-e2e/chain-connected-mvm/setup-chain.sh
./testing-infra/ci-e2e/chain-connected-mvm/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-connected-mvm/deploy-contracts.sh

# Load chain info for balance assertions
source "$PROJECT_ROOT/.tmp/chain-info.env"

echo ""
echo "🚀 Step 4: Configuring and starting verifier (for negotiation routing)..."
echo "=========================================================================="
./testing-infra/ci-e2e/e2e-tests-mvm/start-verifier.sh

# Assert solver has USDcon before starting (should have 1 USDcon from deploy)
assert_usdxyz_balance "solver-chain2" "2" "$TEST_TOKENS_CHAIN2_ADDRESS" "1000000" "pre-solver-start"
echo "   [DEBUG] Balance assertion completed, continuing..."

# Start solver service for automatic signing and fulfillment
echo ""
echo "🚀 Step 4b: Starting solver service..."
echo "======================================="
./testing-infra/ci-e2e/e2e-tests-mvm/start-solver.sh

# Verify solver started successfully
./testing-infra/ci-e2e/verify-solver-running.sh

echo ""
echo "🚀 Step 5: Testing OUTFLOW intents (hub chain → connected chain)..."
echo "===================================================================="
echo "   Submitting outflow cross-chain intents via verifier negotiation routing..."
echo ""
echo "💰 Pre-Intent Balance Validation"
echo "=========================================="
# Everybody starts with 1 USDhub/USDcon on each chain
./testing-infra/ci-e2e/e2e-tests-mvm/balance-check.sh 1000000 1000000 1000000 1000000

./testing-infra/ci-e2e/e2e-tests-mvm/outflow-submit-hub-intent.sh

# Load intent ID for solver fulfillment wait
if ! load_intent_info "INTENT_ID"; then
    echo "❌ ERROR: Failed to load intent info"
    exit 1
fi

echo ""
echo "🤖 Step 5b: Waiting for solver to automatically fulfill..."
echo "==========================================================="
echo "   The solver service is running and will:"
echo "   1. Detect the intent on hub chain"
echo "   2. Transfer tokens to requester on connected MVM chain"
echo "   3. Call verifier to validate and get approval signature"
echo "   4. Fulfill the hub intent with approval"
echo ""

if ! wait_for_solver_fulfillment "$INTENT_ID" "outflow" 60; then
    echo "❌ ERROR: Solver did not fulfill the intent automatically"
    display_service_logs "Solver fulfillment timeout"
    exit 1
fi

echo "✅ Solver fulfilled the intent automatically!"

echo ""
echo "💰 Final Balance View"
echo "=========================================="
# Outflow: Solver gets from hub intent (2000000 on hub, 0 on MVM transferred to requester)
#          Requester receives on MVM (0 on hub locked in intent, 2000000 on MVM)
./testing-infra/ci-e2e/e2e-tests-mvm/balance-check.sh 2000000 0 0 2000000 || true

echo ""
echo "✅ E2E outflow test completed!"
echo ""

echo "🧹 Step 6: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

