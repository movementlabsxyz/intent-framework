#!/bin/bash

# Start Trusted Verifier Service for EVM E2E Tests
# 
# This script configures and starts the trusted verifier service.
# Configuration is done by calling the chain-level configure scripts.

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"

# Setup project root and logging
setup_project_root
setup_logging "verifier-start-evm"
cd "$PROJECT_ROOT"

log ""
log "🚀 Starting Trusted Verifier Service..."
log "========================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

# ============================================================================
# SECTION 1: CONFIGURE VERIFIER
# ============================================================================
log "🔧 Configuring verifier..."

# Configure hub chain section
./testing-infra/ci-e2e/chain-hub/configure-verifier.sh

# Configure connected EVM chain section (also comments out MVM)
./testing-infra/ci-e2e/chain-connected-evm/configure-verifier.sh

# ============================================================================
# SECTION 2: START VERIFIER
# ============================================================================
log ""
log "   Starting verifier service..."
start_verifier "$LOG_DIR/verifier-evm.log" "info"

log ""
log_and_echo "✅ Verifier configured and started successfully"
