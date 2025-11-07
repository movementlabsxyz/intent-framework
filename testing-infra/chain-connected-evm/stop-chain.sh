#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"

# Setup project root and logging
setup_project_root
setup_logging "stop-chain"
cd "$PROJECT_ROOT"

log "🛑 EVM CHAIN CLEANUP"
log "===================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "🧹 Stopping Hardhat node..."

# Kill by PID if exists
if [ -f /tmp/hardhat-node.pid ]; then
    log "   - Found PID file, stopping processes..."
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "     Killing process (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
        fi
    done < /tmp/hardhat-node.pid
    sleep 1
    # Force kill any remaining
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done < /tmp/hardhat-node.pid
    rm -f /tmp/hardhat-node.pid
    log "   ✅ Stopped processes from PID file"
else
    log "   - No PID file found"
fi

# Also try to kill by process name (covers nix develop processes too)
log "   - Killing any remaining Hardhat node processes..."
pkill -f "hardhat node" 2>/dev/null && log "   ✅ Killed Hardhat node processes" || log "   - No Hardhat node processes found"

# Wait a moment for processes to fully terminate
sleep 1

# Verify port 8545 is free
if lsof -i :8545 >/dev/null 2>&1; then
    log "   ⚠️  Warning: Port 8545 is still in use"
    log "   - Attempting to kill process on port 8545..."
    lsof -ti :8545 | xargs kill -9 2>/dev/null || true
    sleep 1
fi

# Note: Hardhat node is stateless - no accounts or state to clean up
# Default accounts are generated fresh on each node start

log ""
log_and_echo "✅ EVM chain cleanup complete"
log ""

