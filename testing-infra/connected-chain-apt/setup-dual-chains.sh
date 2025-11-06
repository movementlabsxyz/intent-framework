#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-dual-chains"
cd "$PROJECT_ROOT"

log "🔗 DUAL-CHAIN APTOS SETUP"
log "=========================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Stop any existing containers
log "🧹 Stopping existing containers..."
docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain1.yml -p aptos-chain1 down 2>/dev/null || true
docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain2.yml -p aptos-chain2 down 2>/dev/null || true

log ""
log "🚀 Starting Chain 1 (ports 8080/8081)..."
docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain1.yml -p aptos-chain1 up -d

log ""
log "🚀 Starting Chain 2 (ports 8082/8083)..."
docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain2.yml -p aptos-chain2 up -d

log ""
log "⏳ Waiting for both chains to start (this may take 2-3 minutes)..."

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
log "🔍 Verifying both chains..."

# Verify Chain 1 is running
log "   - Verifying Chain 1 REST API..."
if ! curl -s http://127.0.0.1:8080/v1 > /dev/null; then
    log_and_echo "❌ Error: Chain 1 failed to start on port 8080"
    exit 1
fi
log "   ✅ Chain 1 REST API is running"

# Verify Chain 2 is running
log "   - Verifying Chain 2 REST API..."
if ! curl -s http://127.0.0.1:8082/v1 > /dev/null; then
    log_and_echo "❌ Error: Chain 2 failed to start on port 8082"
    exit 1
fi
log "   ✅ Chain 2 REST API is running"

# Verify faucets are running
log "   - Verifying faucets..."
FAUCET1_RESPONSE=$(curl -s http://127.0.0.1:8081/ 2>/dev/null || echo "")
FAUCET2_RESPONSE=$(curl -s http://127.0.0.1:8083/ 2>/dev/null || echo "")

if [ "$FAUCET1_RESPONSE" = "tap:ok" ]; then
    log "   ✅ Chain 1 faucet is running"
else
    log_and_echo "❌ Error: Chain 1 faucet failed to start on port 8081"
    exit 1
fi

if [ "$FAUCET2_RESPONSE" = "tap:ok" ]; then
    log "   ✅ Chain 2 faucet is running"
else
    log_and_echo "❌ Error: Chain 2 faucet failed to start on port 8083"
    exit 1
fi

# Show chain status
log ""
log "📊 Chain Status:"
CHAIN1_INFO=$(curl -s http://127.0.0.1:8080/v1 2>/dev/null)
CHAIN1_ID=$(echo "$CHAIN1_INFO" | jq -r '.chain_id // "unknown"' 2>/dev/null)
CHAIN1_HEIGHT=$(echo "$CHAIN1_INFO" | jq -r '.block_height // "unknown"' 2>/dev/null)
CHAIN1_ROLE=$(echo "$CHAIN1_INFO" | jq -r '.node_role // "unknown"' 2>/dev/null)
log "   Chain 1: ID=$CHAIN1_ID, Height=$CHAIN1_HEIGHT, Role=$CHAIN1_ROLE"

CHAIN2_INFO=$(curl -s http://127.0.0.1:8082/v1 2>/dev/null)
CHAIN2_ID=$(echo "$CHAIN2_INFO" | jq -r '.chain_id // "unknown"' 2>/dev/null)
CHAIN2_HEIGHT=$(echo "$CHAIN2_INFO" | jq -r '.block_height // "unknown"' 2>/dev/null)
CHAIN2_ROLE=$(echo "$CHAIN2_INFO" | jq -r '.node_role // "unknown"' 2>/dev/null)
log "   Chain 2: ID=$CHAIN2_ID, Height=$CHAIN2_HEIGHT, Role=$CHAIN2_ROLE"

log ""
log "🎉 Dual-chain setup complete!"
log "   Both chains are running independently with different chain IDs"
log "   Ready for cross-chain testing!"
