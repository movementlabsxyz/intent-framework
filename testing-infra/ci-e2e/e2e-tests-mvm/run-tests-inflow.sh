#!/bin/bash

# E2E Integration Test Runner - INFLOW
# 
# This script runs the inflow E2E tests that require Docker chains.
# It sets up chains, deploys contracts, starts verifier for negotiation routing,
# submits inflow intents via verifier, then runs the tests.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"

# Setup project root
setup_project_root
cd "$PROJECT_ROOT"

echo "🧪 E2E Test with Connected Move VM Chain - INFLOW"
echo "================================================="
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

echo ""
echo "🚀 Step 4: Configuring and starting verifier (for negotiation routing)..."
echo "=========================================================================="
./testing-infra/ci-e2e/e2e-tests-mvm/start-verifier.sh

# Start solver service for automatic signing and fulfillment
echo ""
echo "🚀 Step 4b: Starting solver service..."
echo "======================================="
./testing-infra/ci-e2e/e2e-tests-mvm/start-solver.sh

# Verify solver started successfully
./testing-infra/ci-e2e/verify-solver-running.sh

echo ""
echo "🚀 Step 5: Testing INFLOW intents (connected chain → hub chain)..."
echo "==================================================================="
echo "   Submitting inflow cross-chain intents via verifier negotiation routing..."
./testing-infra/ci-e2e/e2e-tests-mvm/inflow-submit-hub-intent.sh
./testing-infra/ci-e2e/e2e-tests-mvm/inflow-submit-escrow.sh

echo ""
echo "   - Waiting for transactions to be finalized and events to be queryable..."
sleep 5

echo ""
echo "🚀 Step 6: Waiting for solver to automatically fulfill..."
echo "=========================================================="

# Load intent ID for solver fulfillment wait
if ! load_intent_info "INTENT_ID"; then
    echo "❌ ERROR: Failed to load intent info"
    exit 1
fi

echo "   The solver service is running and will:"
echo "   1. Detect the escrow on connected MVM chain"
echo "   2. Fulfill the intent on hub chain"
echo "   3. Verifier will detect fulfillment and generate approval"
echo ""

if ! wait_for_solver_fulfillment "$INTENT_ID" "inflow" 60; then
    echo "❌ ERROR: Solver did not fulfill the intent automatically"
    display_service_logs "Solver fulfillment timeout"
    exit 1
fi

echo "✅ Solver fulfilled the intent automatically!"
echo ""

# Wait for solver to claim escrow (it does this automatically after fulfillment)
echo "⏳ Waiting for solver to claim escrow (5 seconds)..."
sleep 5

echo ""
echo "💰 Final Balance Validation"
echo "=========================================="
# Inflow: Solver transfers to hub requester (0 on hub, 2000000 on MVM from escrow)
#         Requester receives on hub (2000000 on hub, 0 on MVM locked in escrow)
./testing-infra/ci-e2e/e2e-tests-mvm/balance-check.sh 0 2000000 2000000 0

echo ""
echo "✅ E2E inflow test completed!"
echo ""

echo "🧹 Step 7: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

