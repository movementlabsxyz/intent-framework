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

# Setup project root
setup_project_root
cd "$PROJECT_ROOT"

echo "🧪 E2E Test with Connected Move VM Chain - OUTFLOW"
echo "=================================================="
echo ""

echo "🔨 Step 0: Building Rust services (verifier and solver)..."
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

echo "🧹 Step 1: Cleaning up any existing chains, accounts and processes..."
echo "================================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

echo "🚀 Step 2: Setting up chains, deploying contracts, funding accounts"
echo "===================================================================="
./testing-infra/ci-e2e/chain-hub/setup-chain.sh
./testing-infra/ci-e2e/chain-hub/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-hub/deploy-contracts.sh
./testing-infra/ci-e2e/chain-connected-mvm/setup-chain.sh
./testing-infra/ci-e2e/chain-connected-mvm/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-connected-mvm/deploy-contracts.sh

echo ""
echo "🚀 Step 3: Configuring and starting verifier (for negotiation routing)..."
echo "=========================================================================="
./testing-infra/ci-e2e/e2e-tests-mvm/start-verifier.sh

# Start solver service for automatic signing and fulfillment
echo ""
echo "🚀 Step 3b: Starting solver service..."
echo "======================================="
./testing-infra/ci-e2e/e2e-tests-mvm/start-solver.sh

# Verify solver started and show logs if it failed
SOLVER_LOG_FILE="$PROJECT_ROOT/.tmp/intent-framework-logs/solver.log"
if [ -f "$PROJECT_ROOT/.tmp/intent-framework-logs/solver.pid" ]; then
    SOLVER_PID=$(cat "$PROJECT_ROOT/.tmp/intent-framework-logs/solver.pid")
    if ps -p "$SOLVER_PID" > /dev/null 2>&1; then
        echo "✅ Solver is running (PID: $SOLVER_PID)"
        # Show first few lines of solver log to confirm it initialized
        if [ -f "$SOLVER_LOG_FILE" ]; then
            echo "   Solver log (first 20 lines):"
            head -20 "$SOLVER_LOG_FILE" | sed 's/^/   /'
        fi
    else
        echo "❌ ERROR: Solver process died (PID: $SOLVER_PID)"
        if [ -f "$SOLVER_LOG_FILE" ]; then
            echo "   Solver log:"
            cat "$SOLVER_LOG_FILE" | sed 's/^/   /'
        fi
        exit 1
    fi
else
    echo "⚠️  WARNING: Solver PID file not found"
    if [ -f "$SOLVER_LOG_FILE" ]; then
        echo "   Solver log:"
        cat "$SOLVER_LOG_FILE" | sed 's/^/   /'
    fi
fi

echo ""
echo "🚀 Step 4: Testing OUTFLOW intents (hub chain → connected chain)..."
echo "===================================================================="
echo "   Submitting outflow cross-chain intents via verifier negotiation routing..."
./testing-infra/ci-e2e/e2e-tests-mvm/outflow-submit-hub-intent.sh

# Load intent ID for solver fulfillment wait
if ! load_intent_info "INTENT_ID"; then
    echo "❌ ERROR: Failed to load intent info"
    exit 1
fi

echo ""
echo "🤖 Step 4b: Waiting for solver to automatically fulfill..."
echo "==========================================================="
echo "   The solver service is running and will:"
echo "   1. Detect the intent on hub chain"
echo "   2. Transfer tokens to requester on connected MVM chain"
echo "   3. Call verifier to validate and get approval signature"
echo "   4. Fulfill the hub intent with approval"
echo ""

if ! wait_for_solver_fulfillment "$INTENT_ID" "outflow" 90; then
    echo "❌ ERROR: Solver did not fulfill the intent automatically"
    echo "   Check solver logs for errors"
    exit 1
fi

echo "✅ Solver fulfilled the intent automatically!"

echo ""
echo "💰 Final Balance View"
echo "=========================================="
./testing-infra/ci-e2e/e2e-tests-mvm/balance-check.sh || true
echo ""
echo "✅ E2E outflow test flow completed!"
echo ""
echo "📊 Test Summary:"
echo "   ✅ Outflow tests: Tokens transferred from hub chain to connected chain"
echo "   ✅ Verifier negotiation routing: Draft submission and signature retrieval"
echo "   ✅ Solver automation: Solver automatically transferred and fulfilled intent"
echo "   ✅ Verifier automation: Verifier validated transfer and provided approval"
echo ""

echo "🧹 Step 5: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

