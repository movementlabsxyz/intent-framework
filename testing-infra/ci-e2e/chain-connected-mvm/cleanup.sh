#!/bin/bash

# Cleanup for E2E Tests
# 
# This script stops all chains and verifier processes.
# Profile cleanup is handled by individual stop-chain.sh scripts.
# Used by both Aptos and EVM e2e tests.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"

# Setup project root and logging
setup_project_root
setup_logging "cleanup"
cd "$PROJECT_ROOT"

log_and_echo "🧹 Cleaning up chains and processes..."

./testing-infra/ci-e2e/chain-connected-evm/stop-chain.sh || true
./testing-infra/ci-e2e/chain-hub/stop-chain.sh
./testing-infra/ci-e2e/chain-connected-mvm/stop-chain.sh
stop_verifier
stop_solver

# Clean up ephemeral test config to leave clean state
rm -f "$PROJECT_ROOT/testing-infra/ci-e2e/.verifier-keys.env"
rm -f "$PROJECT_ROOT/.tmp/intent-info.env"
rm -f "$PROJECT_ROOT/.tmp/solver-e2e.toml"
rm -f "$PROJECT_ROOT/trusted-verifier/config/verifier-e2e-ci-testing.toml"
rm -f "$PROJECT_ROOT/solver/config/solver-e2e-ci-testing.toml"

log_and_echo "✅ Cleanup complete"

