#!/bin/bash

# Cleanup for E2E Tests
# 
# This script stops all chains and verifier processes.
# Used by both Aptos and EVM e2e tests.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "cleanup"
cd "$PROJECT_ROOT"

log_and_echo "🧹 Cleaning up chains and processes..."

./testing-infra/connected-chain-evm/stop-chain.sh || true
./testing-infra/hub-chain/stop-chain.sh
./testing-infra/connected-chain-apt/stop-chain.sh
pkill -f "trusted-verifier" || true

log_and_echo "✅ Cleanup complete"

