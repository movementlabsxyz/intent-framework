#!/bin/bash

# E2E Integration Test Runner (Mixed-Chain: hub + EVM Escrow)
# 
# This script runs the mixed-chain E2E flow:
# - Chain 1 (hub): Intent creation and fulfillment
# - Chain 3 (EVM): Escrow operations
# - Verifier: Monitors Chain 1 and releases escrow on Chain 3

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

log_and_echo "🧪 E2E Test for Connected EVM Chain"
log_and_echo "======================================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log_and_echo ""

log_and_echo "🧹 Step 1: Cleaning up any existing chains, accounts and processes..."
log_and_echo "=========================================================="
./testing-infra/chain-connected-evm/cleanup.sh
log_and_echo ""

log_and_echo "🚀 Step 2: Setting up chains and deploying contracts..."
log_and_echo "======================================================"
./testing-infra/chain-connected-evm/setup-chain.sh
./testing-infra/chain-connected-evm/setup-requester-solver.sh
./testing-infra/chain-connected-evm/deploy-contract.sh
./testing-infra/chain-hub/setup-chain.sh
./testing-infra/chain-hub/setup-requester-solver.sh
./testing-infra/chain-hub/deploy-contracts.sh

log_and_echo ""
log_and_echo "🚀 Step 3: Submitting cross-chain intents, configuring verifier..."
log_and_echo "==============================================================="
./testing-infra/e2e-tests-evm/inflow-submit-hub-intent.sh
./testing-infra/e2e-tests-evm/inflow-submit-escrow.sh
./testing-infra/e2e-tests-evm/inflow-fulfill-hub-intent.sh
./testing-infra/chain-hub/configure-verifier.sh
./testing-infra/chain-connected-evm/configure-verifier.sh
./testing-infra/e2e-tests-evm/release-escrow.sh

log_and_echo ""
log_and_echo "💰 Final Balance View"
log_and_echo "=========================================="
./testing-infra/e2e-tests-evm/balance-check.sh || true
log_and_echo ""
log_and_echo "✅ E2E test flow completed!"

log_and_echo "🧹 Step 4: Cleaning up chains, accounts and processes..."
log_and_echo "========================================================"
./testing-infra/chain-connected-evm/cleanup.sh