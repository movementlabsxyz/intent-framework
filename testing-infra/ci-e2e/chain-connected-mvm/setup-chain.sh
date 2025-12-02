#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-chain"
cd "$PROJECT_ROOT"

log "🔗 CONNECTED CHAIN SETUP (Chain 2)"
log "==================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Stop any existing container
log "🧹 Stopping existing Chain 2 container..."
docker-compose -f testing-infra/ci-e2e/chain-connected-mvm/docker-compose-connected-chain-mvm.yml -p aptos-chain2 down 2>/dev/null || true

log ""
log "🚀 Starting Chain 2 (ports 8082/8083)..."
docker-compose -f testing-infra/ci-e2e/chain-connected-mvm/docker-compose-connected-chain-mvm.yml -p aptos-chain2 up -d

log ""
log "⏳ Waiting for Chain 2 to start..."

# Wait for Chain 2
wait_for_aptos_chain_ready "2"

log ""
log "🔍 Verifying Chain 2..."

# Verify Chain 2 services
verify_aptos_chain_services "2"

# Show chain status
log ""
log "📊 Chain 2 Status:"
CHAIN2_INFO=$(curl -s http://127.0.0.1:8082/v1 2>/dev/null)
CHAIN2_ID=$(echo "$CHAIN2_INFO" | jq -r '.chain_id // "unknown"' 2>/dev/null)
CHAIN2_HEIGHT=$(echo "$CHAIN2_INFO" | jq -r '.block_height // "unknown"' 2>/dev/null)
CHAIN2_ROLE=$(echo "$CHAIN2_INFO" | jq -r '.node_role // "unknown"' 2>/dev/null)
log "   Chain 2: ID=$CHAIN2_ID, Height=$CHAIN2_HEIGHT, Role=$CHAIN2_ROLE"

log ""
log "🎉 Connected chain setup complete!"
log "   Chain 2 is running on ports 8082 (REST) and 8083 (faucet)"

