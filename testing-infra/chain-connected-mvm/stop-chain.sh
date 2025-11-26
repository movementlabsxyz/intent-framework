#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "stop-chain"
cd "$PROJECT_ROOT"

log "🛑 STOPPING CONNECTED CHAIN (Chain 2)"
log "======================================"

log "🧹 Stopping Chain 2..."
docker-compose -f testing-infra/chain-connected-mvm/docker-compose-connected-chain-mvm.yml -p aptos-chain2 down

log ""
log "🧹 Cleaning up Chain 2 Aptos CLI profiles..."
cleanup_aptos_profile "alice-chain2" "$LOG_FILE"
cleanup_aptos_profile "bob-chain2" "$LOG_FILE"
cleanup_aptos_profile "test-tokens-chain2" "$LOG_FILE"
cleanup_aptos_profile "intent-account-chain2" "$LOG_FILE"

log ""
log_and_echo "✅ Connected chain stopped and accounts cleaned up!"

