#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

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
log "   - Waiting for Chain 1 services..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8080/v1/ledger/info >/dev/null 2>&1 && curl -s http://127.0.0.1:8081/ >/dev/null 2>&1; then
        log "   ✅ Chain 1 ready!"
        break
    fi
    log "   Waiting... (attempt $i/30)"
    sleep 5
done

log ""
log "🔍 Verifying Chain 1..."

# Verify Chain 1 is running
log "   - Verifying Chain 1 REST API..."
if ! curl -s http://127.0.0.1:8080/v1 > /dev/null; then
    log_and_echo "❌ Error: Chain 1 failed to start on port 8080"
    exit 1
fi
log "   ✅ Chain 1 REST API is running"

# Verify faucet is running
log "   - Verifying faucet..."
FAUCET1_RESPONSE=$(curl -s http://127.0.0.1:8081/ 2>/dev/null || echo "")

if [ "$FAUCET1_RESPONSE" = "tap:ok" ]; then
    log "   ✅ Chain 1 faucet is running"
else
    log_and_echo "❌ Error: Chain 1 faucet failed to start on port 8081"
    exit 1
fi

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

