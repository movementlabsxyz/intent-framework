#!/bin/bash

# E2E Integration Test Runner - OUTFLOW
# 
# This script runs the outflow E2E tests that require Docker chains.
# It sets up chains, deploys contracts, submits outflow intents, then runs the tests.

set -e

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
cd "$PROJECT_ROOT"

echo "🧪 E2E Test with Connected Move VM Chain - OUTFLOW"
echo "=================================================="
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

echo ""
echo "🚀 Step 3: Testing OUTFLOW intents (hub chain → connected chain)..."
echo "===================================================================="
echo "   Submitting outflow cross-chain intents..."
./testing-infra/e2e-tests-mvm/outflow-submit-hub-intent.sh
./testing-infra/e2e-tests-mvm/outflow-solver-transfer.sh
./testing-infra/chain-hub/configure-verifier.sh
./testing-infra/chain-connected-mvm/configure-verifier.sh
./testing-infra/e2e-tests-mvm/configure-verifier.sh
./testing-infra/e2e-tests-mvm/start-verifier.sh
./testing-infra/e2e-tests-mvm/outflow-validate-and-fulfill.sh

echo ""
echo "💰 Final Balance View"
echo "=========================================="
./testing-infra/e2e-tests-mvm/balance-check.sh || true
echo ""
echo "✅ E2E outflow test flow completed!"
echo ""
echo "📊 Test Summary:"
echo "   ✅ Outflow tests: Tokens transferred from hub chain to connected chain"
echo ""

echo "🧹 Step 4: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/chain-connected-mvm/cleanup.sh

