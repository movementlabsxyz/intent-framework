#!/bin/bash

# E2E Integration Test Runner (Mixed-Chain: hub + EVM Escrow)
# 
# This script runs the mixed-chain E2E flow:
# - Chain 1 (hub): Intent creation and fulfillment
# - Chain 3 (EVM): Escrow operations
# - Verifier: Provides negotiation routing and monitors chains

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root and logging
setup_project_root
setup_logging "run-tests-evm"
cd "$PROJECT_ROOT"

log_and_echo "🧪 E2E Test for Connected EVM Chain - INFLOW"
log_and_echo "============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log_and_echo ""

log_and_echo "🧹 Step 1: Cleaning up any existing chains, accounts and processes..."
log_and_echo "=========================================================="
./testing-infra/ci-e2e/chain-connected-evm/cleanup.sh
log_and_echo ""

log_and_echo "🚀 Step 2: Setting up chains and deploying contracts..."
log_and_echo "======================================================"
./testing-infra/ci-e2e/chain-connected-evm/setup-chain.sh
./testing-infra/ci-e2e/chain-connected-evm/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-connected-evm/deploy-contract.sh
./testing-infra/ci-e2e/chain-hub/setup-chain.sh
./testing-infra/ci-e2e/chain-hub/setup-requester-solver.sh
./testing-infra/ci-e2e/chain-hub/deploy-contracts.sh

log_and_echo ""
log_and_echo "🚀 Step 3: Configuring and starting verifier (for negotiation routing)..."
log_and_echo "=========================================================================="
./testing-infra/ci-e2e/chain-hub/configure-verifier.sh
./testing-infra/ci-e2e/chain-connected-evm/configure-verifier.sh
./testing-infra/ci-e2e/e2e-tests-evm/start-verifier.sh

log_and_echo ""
log_and_echo "🚀 Step 4: Submitting cross-chain intents via verifier negotiation routing..."
log_and_echo "============================================================================="
./testing-infra/ci-e2e/e2e-tests-evm/inflow-submit-hub-intent.sh
./testing-infra/ci-e2e/e2e-tests-evm/inflow-submit-escrow.sh
./testing-infra/ci-e2e/e2e-tests-evm/inflow-fulfill-hub-intent.sh
./testing-infra/ci-e2e/e2e-tests-evm/release-escrow.sh

log_and_echo ""
log_and_echo "💰 Final Balance View"
log_and_echo "=========================================="
./testing-infra/ci-e2e/e2e-tests-evm/balance-check.sh || true
log_and_echo ""
log_and_echo "✅ E2E test flow completed!"
log_and_echo ""
log_and_echo "📊 Test Summary:"
log_and_echo "   ✅ Inflow tests: Tokens transferred from connected EVM chain to hub chain"
log_and_echo "   ✅ Verifier negotiation routing: Draft submission and signature retrieval"

log_and_echo ""
log_and_echo "🧹 Step 5: Cleaning up chains, accounts and processes..."
log_and_echo "========================================================"
./testing-infra/ci-e2e/chain-connected-evm/cleanup.sh