#!/bin/bash

# Cleanup for E2E Tests
# 
# This script stops all chains and verifier processes.
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

# Delete logs folder for fresh start
rm -rf "$PROJECT_ROOT/.tmp/e2e-tests"

./testing-infra/ci-e2e/chain-connected-evm/stop-chain.sh || true
./testing-infra/ci-e2e/chain-hub/stop-chain.sh
./testing-infra/ci-e2e/chain-connected-mvm/stop-chain.sh
stop_verifier
stop_solver

# Delete target folders to ensure fresh binaries are built
log_and_echo "   Deleting target folders for fresh builds..."
rm -rf "$PROJECT_ROOT/trusted-verifier/target"
rm -rf "$PROJECT_ROOT/solver/target"

# Clean up ephemeral test config to leave clean state
rm -f "$PROJECT_ROOT/testing-infra/ci-e2e/.verifier-keys.env"
rm -f "$PROJECT_ROOT/.tmp/intent-info.env"
rm -f "$PROJECT_ROOT/.tmp/chain-info.env"
rm -f "$PROJECT_ROOT/.tmp/solver-e2e.toml"
rm -f "$PROJECT_ROOT/trusted-verifier/config/verifier-e2e-ci-testing.toml"
rm -f "$PROJECT_ROOT/solver/config/solver-e2e-ci-testing.toml"

log_and_echo "✅ Cleanup complete"

