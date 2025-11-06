#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "stop-chain"
cd "$PROJECT_ROOT"

log "🛑 STOPPING HUB CHAIN (Chain 1)"
log "================================"

log "🧹 Stopping Chain 1..."
docker-compose -f testing-infra/chain-hub/docker-compose-hub-chain.yml -p aptos-chain1 down

log ""
log "🧹 Cleaning up Chain 1 Aptos CLI profiles..."
aptos config delete-profile --profile alice-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile bob-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile intent-account-chain1 >> "$LOG_FILE" 2>&1 || true

log ""
log_and_echo "✅ Hub chain stopped and accounts cleaned up!"

