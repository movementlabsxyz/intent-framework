#!/bin/bash

# E2E Integration Test Runner (Mixed-Chain: Aptos Hub + EVM Escrow)
# 
# This script runs the mixed-chain E2E flow:
# - Chain 1 (Aptos Hub): Intent creation and fulfillment
# - Chain 3 (EVM): Escrow operations
# - Verifier: Monitors Chain 1 and releases escrow on Chain 3

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

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
./testing-infra/e2e-tests-evm/cleanup.sh
log_and_echo ""

log_and_echo "🚀 Step 2: Setting up chains and deploying contracts..."
log_and_echo "======================================================"

./testing-infra/connected-chain-evm/setup-chain.sh
./testing-infra/connected-chain-evm/setup-alice-bob.sh
./testing-infra/connected-chain-evm/deploy-contract.sh

./testing-infra/hub-chain/setup-chain.sh
./testing-infra/hub-chain/setup-alice-bob.sh
./testing-infra/hub-chain/deploy-contracts.sh

./testing-infra/connected-chain-apt/setup-chain.sh
./testing-infra/connected-chain-apt/setup-alice-bob.sh
./testing-infra/connected-chain-apt/deploy-contracts.sh


log_and_echo ""
log_and_echo "🚀 Step 3: Submitting cross-chain intents, configuring verifier..."
log_and_echo "==============================================================="
./testing-infra/e2e-tests-apt/submit-hub-intent.sh
./testing-infra/e2e-tests-evm/submit-escrow.sh
./testing-infra/e2e-tests-apt/fulfill-hub-intent.sh
./testing-infra/e2e-tests-evm/configure-verifier.sh

log_and_echo ""
log_and_echo "🔓 Step 4: Starting verifier and releasing EVM escrow..."
log_and_echo "========================================================"
./testing-infra/e2e-tests-evm/release-escrow.sh

log_and_echo ""
display_balances
log_and_echo ""
log_and_echo "✅ E2E test flow completed!"
log_and_echo ""



log_and_echo ""
log_and_echo "🧹 Step 5: Cleaning up chains, accounts and processes..."
log_and_echo "======================================================="
./testing-infra/e2e-tests-evm/cleanup.sh