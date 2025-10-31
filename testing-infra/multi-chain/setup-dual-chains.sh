#!/bin/bash

# Get project root (this script is typically run from project root)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Setup logging - only log() and log_and_echo() write to log file
LOG_DIR="$PROJECT_ROOT/tmp/intent-framework-logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/setup-dual-chains_${TIMESTAMP}.log"

# Helper function to print important messages to terminal (also logs them)
log_and_echo() {
    echo "$@"
    echo "$@" >> "$LOG_FILE"
}

# Helper function to write only to log file (not terminal)
log() {
    echo "$@" >> "$LOG_FILE"
}

log "🔗 DUAL-CHAIN APTOS SETUP"
log "=========================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Stop any existing containers
log "🧹 Stopping existing containers..."
docker-compose -f testing-infra/multi-chain/docker-compose-chain1.yml -p aptos-chain1 down 2>/dev/null || true
docker-compose -f testing-infra/multi-chain/docker-compose-chain2.yml -p aptos-chain2 down 2>/dev/null || true

log ""
log "🚀 Starting Chain 1 (ports 8080/8081)..."
docker-compose -f testing-infra/multi-chain/docker-compose-chain1.yml -p aptos-chain1 up -d

log ""
log "🚀 Starting Chain 2 (ports 8082/8083)..."
docker-compose -f testing-infra/multi-chain/docker-compose-chain2.yml -p aptos-chain2 up -d

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

# Check Chain 1
CHAIN1_INFO=$(curl -s http://127.0.0.1:8080/v1/ledger/info 2>/dev/null || echo "null")
if [ "$CHAIN1_INFO" != "null" ]; then
    CHAIN1_ID=$(echo "$CHAIN1_INFO" | jq -r '.chain_id // "unknown"')
    CHAIN1_HEIGHT=$(echo "$CHAIN1_INFO" | jq -r '.block_height // "unknown"')
    log "✅ Chain 1: ID=$CHAIN1_ID, Height=$CHAIN1_HEIGHT"
else
    log_and_echo "❌ Chain 1 failed to start"
    exit 1
fi

# Check Chain 2
CHAIN2_INFO=$(curl -s http://127.0.0.1:8082/v1/ledger/info 2>/dev/null || echo "null")
if [ "$CHAIN2_INFO" != "null" ]; then
    CHAIN2_ID=$(echo "$CHAIN2_INFO" | jq -r '.chain_id // "unknown"')
    CHAIN2_HEIGHT=$(echo "$CHAIN2_INFO" | jq -r '.block_height // "unknown"')
    log "✅ Chain 2: ID=$CHAIN2_ID, Height=$CHAIN2_HEIGHT"
else
    log_and_echo "❌ Chain 2 failed to start"
    exit 1
fi

log ""
log "🔗 Dual-Chain Endpoints:"
log "   Chain 1:"
log "     REST API:        http://127.0.0.1:8080"
log "     Faucet:          http://127.0.0.1:8081"
log "   Chain 2:"
log "     REST API:        http://127.0.0.1:8082"
log "     Faucet:          http://127.0.0.1:8083"

log ""
log "📋 Management Commands:"
log "   Stop Chain 1:    docker-compose -f testing-infra/multi-chain/docker-compose-chain1.yml -p aptos-chain1 down"
log "   Stop Chain 2:    docker-compose -f testing-infra/multi-chain/docker-compose-chain2.yml -p aptos-chain2 down"
log "   Stop Both:       ./testing-infra/multi-chain/stop-dual-chains.sh"
log "   Logs Chain 1:    docker-compose -f testing-infra/multi-chain/docker-compose-chain1.yml -p aptos-chain1 logs -f"
log "   Logs Chain 2:    docker-compose -f testing-infra/multi-chain/docker-compose-chain2.yml -p aptos-chain2 logs -f"

log ""
log "🎉 Dual-chain setup complete!"
log "   Both chains are running independently with different chain IDs"
log "   Ready for cross-chain testing!"
