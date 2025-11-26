#!/bin/bash

# E2E Integration Test Runner - OUTFLOW (EVM)
# 
# This script runs the outflow E2E tests with EVM connected chain.
# It sets up chains, deploys contracts, submits outflow intents, then runs the tests.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root and logging
setup_project_root
setup_logging "run-tests-evm-outflow"
cd "$PROJECT_ROOT"

log_and_echo "🧪 E2E Test for Connected EVM Chain - OUTFLOW"
log_and_echo "=============================================="
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
log_and_echo "🚀 Step 3: Testing OUTFLOW intents (hub chain → connected EVM chain)..."
log_and_echo "====================================================================="
log_and_echo "   Submitting outflow cross-chain intents..."
./testing-infra/e2e-tests-evm/outflow-submit-hub-intent.sh
./testing-infra/e2e-tests-evm/outflow-solver-transfer.sh
./testing-infra/chain-hub/configure-verifier.sh
./testing-infra/chain-connected-evm/configure-verifier.sh
./testing-infra/e2e-tests-evm/start-verifier.sh
./testing-infra/e2e-tests-evm/outflow-validate-and-fulfill.sh

log_and_echo ""
log_and_echo "💰 Final Balance View"
log_and_echo "=========================================="
balance_check_evm
log_and_echo ""
log_and_echo "✅ E2E outflow test flow completed!"

log_and_echo ""
log_and_echo "📊 Test Summary:"
log_and_echo "   ✅ Outflow tests: Tokens transferred from hub chain to connected EVM chain"

log_and_echo ""
log_and_echo "🧹 Step 4: Cleaning up chains, accounts and processes..."
log_and_echo "========================================================"
./testing-infra/chain-connected-evm/cleanup.sh

