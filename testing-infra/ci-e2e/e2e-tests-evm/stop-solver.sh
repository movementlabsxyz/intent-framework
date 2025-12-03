#!/bin/bash

# Stop Solver Service
# 
# This script stops the solver service started by start-solver.sh

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"

# Setup project root and logging
setup_project_root
setup_logging "solver-stop-evm"
cd "$PROJECT_ROOT"

log ""
log "🛑 Stopping Solver Service..."
log "========================================"

stop_solver

log ""
log_and_echo "✅ Solver service stopped"

