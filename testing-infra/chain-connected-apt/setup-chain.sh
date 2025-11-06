#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-chain"
cd "$PROJECT_ROOT"

log "🔗 CONNECTED CHAIN SETUP (Chain 2)"
log "==================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Stop any existing container
log "🧹 Stopping existing Chain 2 container..."
docker-compose -f testing-infra/chain-connected-apt/docker-compose-connected-chain-apt.yml -p aptos-chain2 down 2>/dev/null || true

log ""
log "🚀 Starting Chain 2 (ports 8082/8083)..."
docker-compose -f testing-infra/chain-connected-apt/docker-compose-connected-chain-apt.yml -p aptos-chain2 up -d

log ""
log "⏳ Waiting for Chain 2 to start (this may take 2-3 minutes)..."

# Wait for Chain 2
log "   - Waiting for Chain 2 services..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8082/v1/ledger/info >/dev/null 2>&1 && curl -s http://127.0.0.1:8083/ >/dev/null 2>&1; then
        log "   ✅ Chain 2 ready!"
        break
    fi
    log "   Waiting... (attempt $i/30)"
    sleep 5
done

log ""
log "🔍 Verifying Chain 2..."

# Verify Chain 2 is running
log "   - Verifying Chain 2 REST API..."
if ! curl -s http://127.0.0.1:8082/v1 > /dev/null; then
    log_and_echo "❌ Error: Chain 2 failed to start on port 8082"
    exit 1
fi
log "   ✅ Chain 2 REST API is running"

# Verify faucet is running
log "   - Verifying faucet..."
FAUCET2_RESPONSE=$(curl -s http://127.0.0.1:8083/ 2>/dev/null || echo "")

if [ "$FAUCET2_RESPONSE" = "tap:ok" ]; then
    log "   ✅ Chain 2 faucet is running"
else
    log_and_echo "❌ Error: Chain 2 faucet failed to start on port 8083"
    exit 1
fi

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

