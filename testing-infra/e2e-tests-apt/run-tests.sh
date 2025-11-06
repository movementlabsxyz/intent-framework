#!/bin/bash

# E2E Integration Test Runner
# 
# This script runs the Rust integration tests that require Docker chains.
# It sets up chains, deploys contracts, submits intents, then runs the tests.

set -e

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
cd "$PROJECT_ROOT"

echo "🧪 E2E Integration Tests Runner"
echo "================================"
echo ""

echo "🧹 Step -1: Cleaning up any existing chains and processes..."
echo "=========================================================="
./testing-infra/connected-chain-apt/stop-dual-chains.sh
./testing-infra/connected-chain-evm/stop-evm-chain.sh
pkill -f "trusted-verifier" || true
echo "✅ Cleanup complete"
echo ""

echo "🚀 Step 0: Setting up chains, deploying contracts, and submitting intents..."
echo "========================================================================"

./testing-infra/connected-chain-apt/setup-dual-chains.sh
./testing-infra/connected-chain-apt/setup-alice-bob.sh
./testing-infra/e2e-tests-apt/deploy-contracts.sh
./testing-infra/e2e-tests-apt/submit-cross-chain-intent.sh

./testing-infra/e2e-tests-apt/configure-verifier.sh

./testing-infra/e2e-tests-apt/verifier-rust-integration-tests.sh

echo ""
echo "🚀 Step 2: Running verifier service to release escrow..."
echo "======================================================"
./testing-infra/e2e-tests-apt/release-escrow.sh

echo ""
echo "✅ All E2E tests completed!"
echo ""
echo "🧹 Cleaning up Docker chains..."
./testing-infra/connected-chain-apt/stop-dual-chains.sh

