#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_apt.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-chain"
cd "$PROJECT_ROOT"

log "🔗 HUB CHAIN SETUP (Chain 1)"
log "============================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Stop any existing container
log "🧹 Stopping existing Chain 1 container..."
docker-compose -f testing-infra/chain-hub/docker-compose-hub-chain.yml -p aptos-chain1 down 2>/dev/null || true

log ""
log "🚀 Starting Chain 1 (ports 8080/8081)..."
docker-compose -f testing-infra/chain-hub/docker-compose-hub-chain.yml -p aptos-chain1 up -d

log ""
log "⏳ Waiting for Chain 1 to start (this may take 2-3 minutes)..."

# Wait for Chain 1
wait_for_aptos_chain_ready "1"

log ""
log "🔍 Verifying Chain 1..."

# Verify Chain 1 services
verify_aptos_chain_services "1"

# Show chain status
log ""
log "📊 Chain 1 Status:"
CHAIN1_INFO=$(curl -s http://127.0.0.1:8080/v1 2>/dev/null)
CHAIN1_ID=$(echo "$CHAIN1_INFO" | jq -r '.chain_id // "unknown"' 2>/dev/null)
CHAIN1_HEIGHT=$(echo "$CHAIN1_INFO" | jq -r '.block_height // "unknown"' 2>/dev/null)
CHAIN1_ROLE=$(echo "$CHAIN1_INFO" | jq -r '.node_role // "unknown"' 2>/dev/null)
log "   Chain 1: ID=$CHAIN1_ID, Height=$CHAIN1_HEIGHT, Role=$CHAIN1_ROLE"

log ""
log "🎉 Hub chain setup complete!"
log "   Chain 1 is running on ports 8080 (REST) and 8081 (faucet)"

