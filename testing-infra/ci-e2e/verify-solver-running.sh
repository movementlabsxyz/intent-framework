#!/bin/bash

# Verify solver is running script
# Checks if solver process is running and panics if not
# PID (Process ID) is stored in solver.pid file when solver starts

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/util.sh"

# Setup project root
setup_project_root

SOLVER_LOG_FILE="$PROJECT_ROOT/.tmp/e2e-tests/solver.log"
SOLVER_PID_FILE="$PROJECT_ROOT/.tmp/e2e-tests/solver.pid"

# Check if PID file exists
if [ ! -f "$SOLVER_PID_FILE" ]; then
    log_and_echo "❌ PANIC: Solver PID file not found: $SOLVER_PID_FILE"
    log_and_echo "   Solver may not have started successfully"
    display_service_logs "Solver PID file missing"
    exit 1
fi

# Read PID from file
SOLVER_PID=$(cat "$SOLVER_PID_FILE" 2>/dev/null)

if [ -z "$SOLVER_PID" ]; then
    log_and_echo "❌ PANIC: Solver PID file is empty: $SOLVER_PID_FILE"
    display_service_logs "Solver PID file empty"
    exit 1
fi

# Check if process is running
if ! ps -p "$SOLVER_PID" > /dev/null 2>&1; then
    log_and_echo "❌ PANIC: Solver process died (PID: $SOLVER_PID)"
    log_and_echo "   Process ID $SOLVER_PID is not running"
    display_service_logs "Solver process died"
    exit 1
fi

# Solver is running - show confirmation
log_and_echo "✅ Solver is running (PID: $SOLVER_PID)"
if [ -f "$SOLVER_LOG_FILE" ]; then
    log_and_echo "   Solver log (first 20 lines):"
    head -20 "$SOLVER_LOG_FILE" | sed 's/^/   /'
fi

