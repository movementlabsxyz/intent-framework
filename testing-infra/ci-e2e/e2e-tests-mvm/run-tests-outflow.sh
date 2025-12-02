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
./testing-infra/ci-e2e/chain-hub/configure-verifier.sh
./testing-infra/ci-e2e/chain-connected-mvm/configure-verifier.sh
./testing-infra/ci-e2e/e2e-tests-mvm/configure-verifier.sh
./testing-infra/ci-e2e/e2e-tests-mvm/start-verifier.sh

echo ""
echo "🚀 Step 4: Testing OUTFLOW intents (hub chain → connected chain)..."
echo "===================================================================="
echo "   Submitting outflow cross-chain intents via verifier negotiation routing..."
./testing-infra/ci-e2e/e2e-tests-mvm/outflow-submit-hub-intent.sh
./testing-infra/ci-e2e/e2e-tests-mvm/outflow-solver-transfer.sh
./testing-infra/ci-e2e/e2e-tests-mvm/outflow-validate-and-fulfill.sh

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
echo ""

echo "🧹 Step 5: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

