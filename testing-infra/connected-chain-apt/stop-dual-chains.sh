#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "stop-dual-chains"
cd "$PROJECT_ROOT"

log "🛑 STOPPING DUAL-CHAIN SETUP"
log "============================="

log "🧹 Stopping Chain 1..."
docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain1.yml -p aptos-chain1 down

log "🧹 Stopping Chain 2..."
docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain2.yml -p aptos-chain2 down

log ""
log "🧹 Cleaning up Aptos CLI profiles..."
aptos config delete-profile --profile alice-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile bob-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile alice-chain2 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile bob-chain2 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile intent-account-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile intent-account-chain2 >> "$LOG_FILE" 2>&1 || true

log ""
log_and_echo "✅ Both chains stopped and all accounts cleaned up!"
