#!/bin/bash

# E2E Integration Test Runner - Rust Integration Tests
# 
# This script runs the Rust integration tests for verifier and solver.
# It sets up chains, deploys contracts, starts verifier, then runs Rust tests.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"

# Setup project root
setup_project_root
cd "$PROJECT_ROOT"

echo "🧪 Rust Integration Tests"
echo "========================="
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
echo "🚀 Step 4: Configuring and starting verifier..."
echo "================================================"
./testing-infra/ci-e2e/e2e-tests-mvm/start-verifier.sh

echo ""
echo "🚀 Step 5: Running Rust integration tests..."
echo "============================================="
./testing-infra/ci-e2e/e2e-tests-mvm/verifier-rust-integration-tests.sh

echo ""
echo "✅ Rust integration tests completed!"
echo ""

echo "🧹 Step 6: Cleaning up chains, accounts and processes..."
echo "========================================================"
./testing-infra/ci-e2e/chain-connected-mvm/cleanup.sh

