#!/bin/bash

# Start Trusted Verifier Service for E2E Tests (EVM)
# 
# This script starts the trusted verifier service with the configured settings.

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

start_verifier "$LOG_DIR/verifier-evm.log" "info"

log ""
log_and_echo "✅ Verifier started successfully"

