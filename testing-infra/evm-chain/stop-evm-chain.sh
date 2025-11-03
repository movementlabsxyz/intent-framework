#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

setup_project_root
cd "$PROJECT_ROOT"

log "🛑 Stopping Hardhat node..."

# Kill by PID if exists
if [ -f /tmp/hardhat-node.pid ]; then
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "   Killing process (PID: $pid)..."
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
    log "   No PID file found, trying to kill by process name..."
fi

# Also try to kill by process name (covers nix develop processes too)
pkill -f "hardhat node" 2>/dev/null && log "   ✅ Killed Hardhat node processes" || log "   No Hardhat node processes found"

log "✅ Cleanup complete"

