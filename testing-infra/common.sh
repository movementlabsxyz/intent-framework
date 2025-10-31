#!/bin/bash

# Common utilities for testing infrastructure scripts
# Source this file in other scripts with: source "$(dirname "$0")/common.sh" or similar

# Get project root - can be called from any script location
# Usage: Call this function to set PROJECT_ROOT and optionally change to it
# Note: If SCRIPT_DIR is already set by the calling script, use that; otherwise derive from BASH_SOURCE
setup_project_root() {
    local script_dir
    
    # Use SCRIPT_DIR if already set (set by scripts before sourcing)
    if [ -n "$SCRIPT_DIR" ]; then
        script_dir="$SCRIPT_DIR"
    else
        # Get the calling script's path (BASH_SOURCE[1] because [0] is common.sh)
        local script_path="${BASH_SOURCE[1]}"
        if [ -z "$script_path" ]; then
            # Fallback if called differently
            script_path="${BASH_SOURCE[0]}"
        fi
        script_dir="$( cd "$( dirname "$script_path" )" && pwd )"
    fi
    
    # Determine how many levels up to go based on script location
    # Scripts in testing-infra/*/* need to go up 2 levels
    # Scripts in testing-infra/* need to go up 1 level
    if [[ "$script_dir" == *"/testing-infra/"*"/"* ]]; then
        # Script is in a subdirectory (e.g., testing-infra/e2e-tests/move-intent-framework/)
        PROJECT_ROOT="$( cd "$script_dir/../../.." && pwd )"
    else
        # Script is directly in testing-infra/
        PROJECT_ROOT="$( cd "$script_dir/../.." && pwd )"
    fi
    
    export PROJECT_ROOT
}

# Setup logging functions and directory
# Usage: setup_logging "script-name"
# Creates log file: tmp/intent-framework-logs/script-name_TIMESTAMP.log
setup_logging() {
    local script_name="${1:-script}"
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    LOG_DIR="$PROJECT_ROOT/tmp/intent-framework-logs"
    mkdir -p "$LOG_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="$LOG_DIR/${script_name}_${TIMESTAMP}.log"
    
    export LOG_DIR LOG_FILE TIMESTAMP
}

# Helper function to print important messages to terminal (also logs them)
log_and_echo() {
    echo "$@"
    [ -n "$LOG_FILE" ] && echo "$@" >> "$LOG_FILE"
}

# Helper function to write only to log file (not terminal)
log() {
    [ -n "$LOG_FILE" ] && echo "$@" >> "$LOG_FILE"
}

# Fetch and display balances
# Usage: display_balances
# Fetches balances from aptos CLI and displays them on both terminal and log file
display_balances() {
    # Fetch balances
    local alice1=$(aptos account balance --profile alice-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    local alice2=$(aptos account balance --profile alice-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    local bob1=$(aptos account balance --profile bob-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    local bob2=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    
    log_and_echo ""
    log_and_echo "   Chain 1 (Hub):"
    log_and_echo "      Alice: $alice1 Octas"
    log_and_echo "      Bob:   $bob1 Octas"
    log_and_echo "   Chain 2 (Connected):"
    log_and_echo "      Alice: $alice2 Octas"
    log_and_echo "      Bob:   $bob2 Octas"
    log_and_echo ""
}


