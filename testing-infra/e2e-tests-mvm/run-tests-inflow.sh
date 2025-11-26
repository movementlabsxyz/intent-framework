#!/bin/bash

# E2E Integration Test Runner - INFLOW
# 
# This script runs the inflow E2E tests that require Docker chains.
# It sets up chains, deploys contracts, submits inflow intents, then runs the tests.

set -e

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
cd "$PROJECT_ROOT"

echo "🧪 E2E Test with Connected Move VM Chain - INFLOW"
echo "================================================="
echo ""

echo "🧹 Step 1: Cleaning up any existing chains, accounts and processes..."
echo "================================================================"
./testing-infra/chain-connected-mvm/cleanup.sh

echo "🚀 Step 2: Setting up chains, deploying contracts, funding accounts"
echo "===================================================================="
./testing-infra/chain-hub/setup-chain.sh
./testing-infra/chain-hub/setup-requester-solver.sh
./testing-infra/chain-hub/deploy-contracts.sh
./testing-infra/chain-connected-mvm/setup-chain.sh
./testing-infra/chain-connected-mvm/setup-requester-solver.sh
./testing-infra/chain-connected-mvm/deploy-contracts.sh

echo "🚀 Step 3: Testing INFLOW intents (connected chain → hub chain)..."
echo "==================================================================="
echo "   Submitting inflow cross-chain intents..."
./testing-infra/e2e-tests-mvm/inflow-submit-hub-intent.sh
./testing-infra/e2e-tests-mvm/inflow-submit-escrow.sh

echo ""
echo "🚀 Step 4: Configuring verifier..."
echo "===================================="
./testing-infra/chain-hub/configure-verifier.sh
./testing-infra/chain-connected-mvm/configure-verifier.sh
./testing-infra/e2e-tests-mvm/configure-verifier.sh

echo ""
echo "   - Waiting for transactions to be finalized and events to be queryable..."
sleep 5

echo ""
echo "🚀 Step 5: Completing inflow flow (fulfillment and escrow release)..."
echo "==================================================================="
./testing-infra/e2e-tests-mvm/inflow-fulfill-hub-intent.sh
./testing-infra/e2e-tests-mvm/start-verifier.sh
./testing-infra/e2e-tests-mvm/release-escrow.sh

echo ""
echo "🚀 Step 6: Running Rust integration tests..."
echo "============================================"
./testing-infra/e2e-tests-mvm/verifier-rust-integration-tests.sh

echo ""
echo "✅ E2E inflow test flow completed!"
echo ""
echo "📊 Test Summary:"
echo "   ✅ Inflow tests: Tokens transferred from connected chain to hub chain"
echo ""

echo "🧹 Step 7: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/chain-connected-mvm/cleanup.sh

