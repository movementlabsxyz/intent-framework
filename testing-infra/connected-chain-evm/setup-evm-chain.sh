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
log "📦 Installing npm dependencies..."
cd evm-intent-framework

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
    log "   Running npm install..."
    nix develop -c bash -c "npm install" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_and_echo "   ❌ ERROR: npm install failed"
        log_and_echo "   Check log file for details: $LOG_FILE"
        exit 1
    fi
    log "   ✅ Dependencies installed"
else
    log "   ✅ Dependencies already installed"
fi

log ""
log "🚀 Starting Hardhat node on port 8545..."

# Start Hardhat node in background (run in nix develop)
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
# Timeout set to 180 seconds (3 minutes) for CI environments
for i in {1..180}; do
    CURL_RESPONSE=$(curl -s -X POST http://127.0.0.1:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>&1)
    CURL_EXIT_CODE=$?
    
    if [ $CURL_EXIT_CODE -eq 0 ] && echo "$CURL_RESPONSE" | grep -q '"result"'; then
        log "   ✅ Hardhat node ready!"
        break
    fi
    
    # Log progress every 30 seconds
    if [ $((i % 30)) -eq 0 ]; then
        log "   Still waiting... (${i}/180 seconds)"
        if [ $CURL_EXIT_CODE -ne 0 ]; then
            log "   Curl error (exit code: $CURL_EXIT_CODE): $CURL_RESPONSE"
        elif [ -n "$CURL_RESPONSE" ]; then
            log "   Curl response: $CURL_RESPONSE"
        fi
    fi
    
    if [ $i -eq 180 ]; then
        log_and_echo "   ❌ Timeout waiting for Hardhat node (180 seconds)"
        log_and_echo "   Checking process status..."
        if ps -p "$HARDHAT_PID" > /dev/null 2>&1; then
            log_and_echo "   Process $HARDHAT_PID is still running"
        else
            log_and_echo "   Process $HARDHAT_PID is not running (may have crashed)"
        fi
        log_and_echo "   Last 50 lines of Hardhat log:"
        if [ -f "$LOG_FILE" ]; then
            tail -50 "$LOG_FILE" | while IFS= read -r line; do
                log_and_echo "   $line"
            done
        else
            log_and_echo "   Log file not found: $LOG_FILE"
        fi
        log_and_echo "   Checking if port 8545 is in use:"
        if command -v lsof > /dev/null 2>&1; then
            if lsof -i :8545 > /dev/null 2>&1; then
                log_and_echo "   Port 8545 is in use by:"
                lsof -i :8545 | while IFS= read -r line; do
                    log_and_echo "   $line"
                done
            else
                log_and_echo "   Port 8545 is not in use (according to lsof)"
            fi
        elif command -v ss > /dev/null 2>&1; then
            if ss -tuln | grep -q ':8545'; then
                log_and_echo "   Port 8545 appears to be in use (according to ss):"
                ss -tulnp | grep ':8545' | while IFS= read -r line; do
                    log_and_echo "   $line"
                done
            else
                log_and_echo "   Port 8545 is not in use (according to ss)"
            fi
        else
            log_and_echo "   Cannot check port status (lsof/ss not available)"
        fi
        log_and_echo "   Final curl test response:"
        log_and_echo "   $CURL_RESPONSE"
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
log "   Stop node:      ./testing-infra/connected-chain-evm/stop-evm-chain.sh"
log "   View logs:      tail -f $LOG_FILE"
log "   Check status:   curl -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
log ""
log "🎉 EVM chain setup complete!"

