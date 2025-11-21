#!/bin/bash

# Common utilities for testing infrastructure scripts
# Source this file in other scripts with: source "$(dirname "$0")/util.sh" or similar

# Get project root - can be called from any script location
# Usage: Call this function to set PROJECT_ROOT and optionally change to it
# Note: If SCRIPT_DIR is already set by the calling script, use that; otherwise derive from BASH_SOURCE
setup_project_root() {
    local script_dir
    
    # Use SCRIPT_DIR if already set (set by scripts before sourcing)
    if [ -n "$SCRIPT_DIR" ]; then
        script_dir="$SCRIPT_DIR"
    else
        # Get the calling script's path (BASH_SOURCE[1] because [0] is util.sh)
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
        # Script is in a subdirectory (e.g., testing-infra/e2e-tests-mvm/)
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
    echo "$@"
    [ -n "$LOG_FILE" ] && echo "$@" >> "$LOG_FILE"
}

# Setup verifier configuration
# Usage: setup_verifier_config
# Sets up the verifier testing configuration file path and exports it
# This function is used by configure-verifier.sh scripts and e2e tests
setup_verifier_config() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    VERIFIER_TESTING_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testing.toml"

    if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
        log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
        log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
        exit 1
    fi

    # Export config path for Rust code to use (absolute path so tests can find it)
    export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

    log "   ✅ Verifier config set: $VERIFIER_CONFIG_PATH"
}

# Save intent information to file
# Usage: save_intent_info [intent_id] [hub_intent_address]
# If arguments are provided, uses them; otherwise uses INTENT_ID and HUB_INTENT_ADDRESS env vars
# Saves to ${PROJECT_ROOT}/tmp/intent-info.env
save_intent_info() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    local intent_id="${1:-$INTENT_ID}"
    local hub_intent_address="${2:-$HUB_INTENT_ADDRESS}"

    if [ -z "$intent_id" ]; then
        log_and_echo "❌ ERROR: save_intent_info() requires INTENT_ID"
        exit 1
    fi

    INTENT_INFO_FILE="${PROJECT_ROOT}/tmp/intent-info.env"
    mkdir -p "$(dirname "$INTENT_INFO_FILE")"
    
    echo "INTENT_ID=$intent_id" > "$INTENT_INFO_FILE"
    
    if [ -n "$hub_intent_address" ] && [ "$hub_intent_address" != "null" ]; then
        echo "HUB_INTENT_ADDRESS=$hub_intent_address" >> "$INTENT_INFO_FILE"
    fi
    
    log "   📝 Intent info saved to: $INTENT_INFO_FILE"
}

# Load intent information from file
# Usage: load_intent_info [required_vars]
#   required_vars: comma-separated list of required variables (e.g., "INTENT_ID,HUB_INTENT_ADDRESS")
#   If not provided, only INTENT_ID is required
#   If INTENT_ID is already set, skips loading (allows override via env var)
# Loads from ${PROJECT_ROOT}/tmp/intent-info.env
load_intent_info() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    local required_vars="${1:-INTENT_ID}"
    INTENT_INFO_FILE="${PROJECT_ROOT}/tmp/intent-info.env"

    # If INTENT_ID is already set and only INTENT_ID is required, skip loading
    if [ "$required_vars" = "INTENT_ID" ] && [ -n "$INTENT_ID" ]; then
        log "   ✅ INTENT_ID already set, skipping load"
        return 0
    fi

    if [ ! -f "$INTENT_INFO_FILE" ]; then
        log_and_echo "❌ ERROR: intent-info.env not found at $INTENT_INFO_FILE"
        if [ "$required_vars" = "INTENT_ID,HUB_INTENT_ADDRESS" ]; then
            log_and_echo "   Run inflow-submit-hub-intent.sh first, or provide INTENT_ID=<id> and HUB_INTENT_ADDRESS=<address>"
        else
            log_and_echo "   Run inflow-submit-hub-intent.sh first, or provide INTENT_ID=<id>"
        fi
        exit 1
    fi

    source "$INTENT_INFO_FILE"
    log "   ✅ Loaded intent info from $INTENT_INFO_FILE"

    # Validate required variables
    IFS=',' read -ra VARS <<< "$required_vars"
    for var in "${VARS[@]}"; do
        var=$(echo "$var" | tr -d ' ')
        local value="${!var}"
        if [ -z "$value" ]; then
            log_and_echo "❌ ERROR: $var not found in intent-info.env"
            if [ "$required_vars" = "INTENT_ID,HUB_INTENT_ADDRESS" ]; then
                log_and_echo "   Run inflow-submit-hub-intent.sh first"
            fi
            exit 1
        fi
    done

    return 0
}

# Stop verifier processes
# Usage: stop_verifier
# Stops any running trusted-verifier processes
stop_verifier() {
    log "   Checking for existing verifiers..."
    
    if pgrep -f "cargo.*trusted-verifier" > /dev/null || pgrep -f "target/debug/trusted-verifier" > /dev/null; then
        log "   ⚠️  Found existing verifier processes, stopping them..."
        pkill -f "cargo.*trusted-verifier" || true
        pkill -f "target/debug/trusted-verifier" || true
        sleep 2
        log "   ✅ Verifier processes stopped"
    else
        log "   ✅ No existing verifier processes"
    fi
}

# Check verifier health
# Usage: check_verifier_health [port]
# Checks if verifier health endpoint responds
# Returns 0 if healthy, 1 if not
check_verifier_health() {
    local port="${1:-3333}"
    
    if curl -s -f "http://127.0.0.1:${port}/health" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Start verifier service
# Usage: start_verifier [log_file] [rust_log_level]
# Starts trusted-verifier in background and waits for it to be ready
# Sets VERIFIER_PID and VERIFIER_LOG global variables
# Exits with error if verifier fails to start
start_verifier() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    if [ -z "$VERIFIER_CONFIG_PATH" ]; then
        setup_verifier_config
    fi

    local log_file="${1:-$LOG_DIR/verifier.log}"
    local rust_log="${2:-info}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"
    
    # Stop any existing verifier first
    stop_verifier
    
    log "   Starting verifier service..."
    log "   Using config: $VERIFIER_CONFIG_PATH"
    log "   Log file: $log_file"
    
    # Change to trusted-verifier directory and start the verifier
    pushd "$PROJECT_ROOT/trusted-verifier" > /dev/null
    VERIFIER_CONFIG_PATH="$VERIFIER_CONFIG_PATH" RUST_LOG="$rust_log" cargo run --bin trusted-verifier > "$log_file" 2>&1 &
    VERIFIER_PID=$!
    popd > /dev/null
    
    log "   ✅ Verifier started with PID: $VERIFIER_PID"
    
    # Wait for verifier to be ready
    log "   - Waiting for verifier to initialize..."
    RETRY_COUNT=0
    MAX_RETRIES=180
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Check if process is still running
        if ! ps -p "$VERIFIER_PID" > /dev/null 2>&1; then
            log_and_echo "   ❌ Verifier process died"
            log_and_echo "   Verifier log:"
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
            if [ -f "$log_file" ]; then
                log_and_echo "   $(cat "$log_file")"
            else
                log_and_echo "   Log file not found at: $log_file"
            fi
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
            exit 1
        fi
        
        # Check health endpoint
        if check_verifier_health; then
            log "   ✅ Verifier is ready!"
            
            # Give verifier time to start polling and collect initial events
            log "   - Waiting for verifier to poll and collect events (30 seconds)..."
            sleep 30
            
            VERIFIER_LOG="$log_file"
            export VERIFIER_PID VERIFIER_LOG
            return 0
        fi
        
        sleep 1
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    
    # If we get here, verifier didn't become healthy
    log_and_echo "   ❌ Verifier failed to start after $MAX_RETRIES seconds"
    log_and_echo "   Verifier log:"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    if [ -f "$log_file" ]; then
        log_and_echo "   $(cat "$log_file")"
    else
        log_and_echo "   Log file not found at: $log_file"
    fi
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
}

