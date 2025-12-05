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
echo "🚀 Step 4: Testing INFLOW intents (connected chain → hub chain)..."
echo "==================================================================="
echo "   Submitting inflow cross-chain intents via verifier negotiation routing..."
./testing-infra/ci-e2e/e2e-tests-mvm/inflow-submit-hub-intent.sh
./testing-infra/ci-e2e/e2e-tests-mvm/inflow-submit-escrow.sh

echo ""
echo "   - Waiting for transactions to be finalized and events to be queryable..."
sleep 5

echo ""
echo "🚀 Step 5: Completing inflow flow (fulfillment and escrow release)..."
echo "==================================================================="
./testing-infra/ci-e2e/e2e-tests-mvm/inflow-fulfill-hub-intent.sh
./testing-infra/ci-e2e/e2e-tests-mvm/release-escrow.sh

echo ""
echo "💰 Final Balance View"
echo "=========================================="
./testing-infra/ci-e2e/e2e-tests-mvm/balance-check.sh || true
echo ""
echo "✅ E2E inflow test flow completed!"
echo ""
echo "📊 Test Summary:"
echo "   ✅ Inflow tests: Tokens transferred from connected chain to hub chain"
echo "   ✅ Verifier negotiation routing: Draft submission and signature retrieval"
echo ""

echo "🧹 Step 6: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

