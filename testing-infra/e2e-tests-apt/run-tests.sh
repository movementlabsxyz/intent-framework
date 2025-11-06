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

echo "🧹 Step 1: Cleaning up any existing chains, accounts and processes..."
echo "================================================================"
./testing-infra/cleanup.sh

echo "🚀 Step 2: Setting up chains, deploying contracts, funding accounts"
echo "===================================================================="
./testing-infra/connected-chain-apt/setup-dual-chains.sh
./testing-infra/connected-chain-apt/setup-alice-bob.sh
./testing-infra/e2e-tests-apt/deploy-contracts.sh

echo ""
echo "🚀 Step 3: Submitting cross-chain intents, configuring verifier..."
echo "================================================================"
./testing-infra/e2e-tests-apt/submit-cross-chain-intent.sh
./testing-infra/e2e-tests-apt/configure-verifier.sh

echo ""
echo "🚀 Step 4: Running Rust integration tests..."
echo "======================================================="
./testing-infra/e2e-tests-apt/verifier-rust-integration-tests.sh

echo ""
echo "🚀 Step 5: Running verifier service to release escrow..."
echo "========================================================="
./testing-infra/e2e-tests-apt/release-escrow.sh

echo ""
echo "✅ E2E test flow completed!"
echo ""
echo "🧹 Step 6: Cleaning up chains, accounts and processes..."
echo "======================================="
./testing-infra/cleanup.sh
