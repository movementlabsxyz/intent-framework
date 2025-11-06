#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "stop-connected-chain"
cd "$PROJECT_ROOT"

log "🛑 STOPPING CONNECTED CHAIN (Chain 2)"
log "======================================"

log "🧹 Stopping Chain 2..."
docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain2.yml -p aptos-chain2 down

log ""
log "🧹 Cleaning up Chain 2 Aptos CLI profiles..."
aptos config delete-profile --profile alice-chain2 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile bob-chain2 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile intent-account-chain2 >> "$LOG_FILE" 2>&1 || true

log ""
log_and_echo "✅ Connected chain stopped and accounts cleaned up!"

