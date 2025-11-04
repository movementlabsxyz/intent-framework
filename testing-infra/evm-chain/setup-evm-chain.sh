#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "setup-evm-chain"
cd "$PROJECT_ROOT"

log "🔗 EVM CHAIN SETUP"
log "=================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Stop any existing Hardhat node
log "🧹 Stopping any existing Hardhat node..."
pkill -f "hardhat node" || true
sleep 2

log ""
log "🚀 Starting Hardhat node on port 8545..."

# Start Hardhat node in background (run in nix develop)
cd evm-intent-framework
nix develop -c bash -c "npx hardhat node --port 8545" > "$LOG_FILE" 2>&1 &
HARDHAT_PID=$!

# Save PID for cleanup (both the nix process and we'll track hardhat process separately)
echo "$HARDHAT_PID" > /tmp/hardhat-node.pid

# Also track the actual hardhat process (in case we need to kill it directly)
sleep 2
HARDHAT_CHILD_PID=$(pgrep -P $HARDHAT_PID -f "hardhat node" | head -1)
if [ -n "$HARDHAT_CHILD_PID" ]; then
    echo "$HARDHAT_CHILD_PID" >> /tmp/hardhat-node.pid
fi

log "   Hardhat node started with PID: $HARDHAT_PID"

log ""
log "⏳ Waiting for Hardhat node to be ready..."

# Wait for node to be ready (check if port 8545 is responding)
# Increased timeout to 60 seconds for CI environments
for i in {1..60}; do
    if curl -s -X POST http://127.0.0.1:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        >/dev/null 2>&1; then
        log "   ✅ Hardhat node ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        log_and_echo "   ❌ Timeout waiting for Hardhat node"
        kill "$HARDHAT_PID" 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

cd ..

log ""
log "✅ EVM chain (Hardhat) is running!"
log ""
log "📋 Hardhat Node Details:"
log "   RPC URL:    http://127.0.0.1:8545"
log "   Chain ID:   31337"
log "   PID:        $HARDHAT_PID"
log ""
log "   ... (20 accounts total)"
log ""
log "   Private keys available via: npx hardhat node"
log ""
log "📋 Management Commands:"
log "   Stop node:      ./testing-infra/e2e-tests-evm/evm-chain/stop-evm-chain.sh"
log "   View logs:      tail -f $LOG_FILE"
log "   Check status:   curl -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
log ""
log "🎉 EVM chain setup complete!"

