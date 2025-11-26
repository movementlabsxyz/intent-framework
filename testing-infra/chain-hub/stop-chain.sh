#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

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
cleanup_aptos_profile "alice-chain1" "$LOG_FILE"
cleanup_aptos_profile "bob-chain1" "$LOG_FILE"
cleanup_aptos_profile "test-tokens-chain1" "$LOG_FILE"
cleanup_aptos_profile "intent-account-chain1" "$LOG_FILE"

log ""
log_and_echo "✅ Hub chain stopped and accounts cleaned up!"

