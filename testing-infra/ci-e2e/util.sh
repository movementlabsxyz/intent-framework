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
        # Script is in a subdirectory (e.g., testing-infra/ci-e2e/e2e-tests-mvm/)
        PROJECT_ROOT="$( cd "$script_dir/../../.." && pwd )"
    else
        # Script is directly in testing-infra/
        PROJECT_ROOT="$( cd "$script_dir/../.." && pwd )"
    fi
    
    export PROJECT_ROOT
}

# Setup logging functions and directory
# Usage: setup_logging "script-name"
# Creates log file: .tmp/e2e-tests/script-name.log
setup_logging() {
    local script_name="${1:-script}"
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    LOG_DIR="$PROJECT_ROOT/.tmp/e2e-tests"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/${script_name}.log"
    
    export LOG_DIR LOG_FILE
}

# Helper function to print important messages to terminal (also logs them)
log_and_echo() {
    echo "$@"
    [ -n "$LOG_FILE" ] && echo "$@" >> "$LOG_FILE"
    return 0  # Prevent set -e from exiting on [ -n "$LOG_FILE" ] returning false
}

# Helper function to write only to log file (not terminal)
log() {
    echo "$@"
    [ -n "$LOG_FILE" ] && echo "$@" >> "$LOG_FILE"
    return 0  # Prevent set -e from exiting on [ -n "$LOG_FILE" ] returning false
}

# Setup verifier configuration
# Usage: generate_verifier_keys
# Generates fresh ephemeral keys for E2E/CI testing and exports them as env vars.
# Also creates a minimal config file so get_verifier_eth_address can read the keys.
# Keys are saved to testing-infra/ci-e2e/.verifier-keys.env during the test run,
# but cleanup deletes this file at the start of each test run, ensuring fresh keys every time.
# If keys already exist (from a previous call in same test run), loads them instead.
generate_verifier_keys() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    VERIFIER_KEYS_FILE="$PROJECT_ROOT/testing-infra/ci-e2e/.verifier-keys.env"
    VERIFIER_CONFIG_FILE="$PROJECT_ROOT/trusted-verifier/config/verifier-e2e-ci-testing.toml"

    # If keys already exist, just load them
    if [ -f "$VERIFIER_KEYS_FILE" ]; then
        source "$VERIFIER_KEYS_FILE"
        export E2E_VERIFIER_PRIVATE_KEY
        export E2E_VERIFIER_PUBLIC_KEY
        log_and_echo "   ✅ Loaded existing ephemeral keys"
        return
    fi

    log_and_echo "   Generating ephemeral test keys..."
    cd "$PROJECT_ROOT/trusted-verifier"
    
    # Build and run generate_keys, capture output
    KEYS_OUTPUT=$(cargo run --bin generate_keys 2>/dev/null)
    
    # Extract keys from output
    PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep "Private Key (base64):" | sed 's/.*: //')
    PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep "Public Key (base64):" | sed 's/.*: //')
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        log_and_echo "❌ ERROR: Failed to generate test keys"
        exit 1
    fi
    
    # Export keys as environment variables (E2E prefix to avoid collision)
    export E2E_VERIFIER_PRIVATE_KEY="$PRIVATE_KEY"
    export E2E_VERIFIER_PUBLIC_KEY="$PUBLIC_KEY"
    
    # Save keys to file for reuse within the same test run (cleanup deletes it at start of next run)
    cat > "$VERIFIER_KEYS_FILE" << EOF
# Ephemeral verifier keys for E2E/CI testing
# Generated at: $(date)
# WARNING: These keys are for testing only. Do not use in production.
E2E_VERIFIER_PRIVATE_KEY="$PRIVATE_KEY"
E2E_VERIFIER_PUBLIC_KEY="$PUBLIC_KEY"
EOF

    # Create minimal config file so get_verifier_eth_address can read keys
    # This will be overwritten by configure-verifier.sh with full config
    cat > "$VERIFIER_CONFIG_FILE" << EOF
# Minimal config for key access - will be overwritten by configure-verifier.sh

[hub_chain]
name = "Hub Chain"
rpc_url = "http://127.0.0.1:8080"
chain_id = 1
intent_module_address = "0x123"

[verifier]
private_key_env = "E2E_VERIFIER_PRIVATE_KEY"
public_key_env = "E2E_VERIFIER_PUBLIC_KEY"
polling_interval_ms = 2000
validation_timeout_ms = 30000

[api]
host = "127.0.0.1"
port = 3333
cors_origins = []
EOF
    
    cd "$PROJECT_ROOT"
    log_and_echo "   ✅ Generated fresh ephemeral keys"
}

# Usage: load_verifier_keys
# Loads previously generated keys from the keys file.
load_verifier_keys() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    VERIFIER_KEYS_FILE="$PROJECT_ROOT/testing-infra/ci-e2e/.verifier-keys.env"

    if [ -f "$VERIFIER_KEYS_FILE" ]; then
        source "$VERIFIER_KEYS_FILE"
        export E2E_VERIFIER_PRIVATE_KEY
        export E2E_VERIFIER_PUBLIC_KEY
    else
        log_and_echo "❌ ERROR: Verifier keys file not found at $VERIFIER_KEYS_FILE"
        log_and_echo "   Run generate_verifier_keys first."
        exit 1
    fi
}

# Setup solver configuration for E2E/CI testing
# Usage: setup_solver_config
# Always creates config from template (overwrites any existing config)
# This function is used by E2E test scripts
#
# SECURITY: This function ALWAYS creates a fresh config from template for E2E/CI testing.
# Test scripts should populate it with ephemeral/test addresses and keys.
setup_solver_config() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    SOLVER_E2E_CI_TESTING_CONFIG="$PROJECT_ROOT/solver/config/solver-e2e-ci-testing.toml"
    SOLVER_TEMPLATE="$PROJECT_ROOT/solver/config/solver.template.toml"

    # Always recreate config from template (ensures fresh config for each test run)
    log_and_echo "   Creating solver-e2e-ci-testing.toml from template..."
    
    if [ ! -f "$SOLVER_TEMPLATE" ]; then
        log_and_echo "❌ ERROR: solver.template.toml not found at $SOLVER_TEMPLATE"
        exit 1
    fi
    
    # Copy template (overwrites any existing config file)
    cp "$SOLVER_TEMPLATE" "$SOLVER_E2E_CI_TESTING_CONFIG"
    
    cd "$PROJECT_ROOT"
    log_and_echo "   ✅ Created solver-e2e-ci-testing.toml from template"

    # Export config path for Rust code to use (absolute path so tests can find it)
    export SOLVER_CONFIG_PATH="$SOLVER_E2E_CI_TESTING_CONFIG"

    log "   ✅ Solver config set: $SOLVER_CONFIG_PATH"
}

# Save intent information to file
# Usage: save_intent_info [intent_id] [hub_intent_address]
# If arguments are provided, uses them; otherwise uses INTENT_ID and HUB_INTENT_ADDRESS env vars
# Saves to ${PROJECT_ROOT}/.tmp/intent-info.env
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

    INTENT_INFO_FILE="${PROJECT_ROOT}/.tmp/intent-info.env"
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
# Loads from ${PROJECT_ROOT}/.tmp/intent-info.env
load_intent_info() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    local required_vars="${1:-INTENT_ID}"
    INTENT_INFO_FILE="${PROJECT_ROOT}/.tmp/intent-info.env"

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

# Check if port is listening
# Usage: check_port_listening [port]
# Returns 0 if port is listening, 1 if not
check_port_listening() {
    local port="${1:-3333}"
    
    # Try different methods depending on what's available
    if command -v ss > /dev/null 2>&1; then
        ss -ln | grep -q ":${port} " && return 0
    elif command -v netstat > /dev/null 2>&1; then
        netstat -ln | grep -q ":${port} " && return 0
    elif command -v lsof > /dev/null 2>&1; then
        lsof -i ":${port}" > /dev/null 2>&1 && return 0
    fi
    
    # Fallback: try to connect to the port
    if command -v nc > /dev/null 2>&1; then
        nc -z 127.0.0.1 "${port}" > /dev/null 2>&1 && return 0
    fi
    
    return 1
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

# Verify verifier is running
# Usage: verify_verifier_running
# Checks verifier process, port, and health endpoint
# Exits with error if verifier is not running
verify_verifier_running() {
    # Ensure LOG_DIR is set (for reading PID files)
    if [ -z "$LOG_DIR" ] && [ -n "$PROJECT_ROOT" ]; then
        LOG_DIR="$PROJECT_ROOT/.tmp/e2e-tests"
    fi
    
    log ""
    log "🔍 Verifying verifier is running..."
    
    # Try to load VERIFIER_PID from file if not set
    if [ -z "$VERIFIER_PID" ] && [ -n "$LOG_DIR" ] && [ -f "$LOG_DIR/verifier.pid" ]; then
        VERIFIER_PID=$(cat "$LOG_DIR/verifier.pid" 2>/dev/null || echo "")
        export VERIFIER_PID
    fi
    
    # Check verifier process
    if [ -z "$VERIFIER_PID" ] || ! ps -p "$VERIFIER_PID" > /dev/null 2>&1; then
        log_and_echo "❌ ERROR: Verifier process is not running"
        log_and_echo "   Expected PID: ${VERIFIER_PID:-<not set>}"
        log_and_echo "   Please start verifier first using start-verifier.sh"
        exit 1
    fi
    
    # Check if verifier port is listening
    VERIFIER_PORT="${VERIFIER_PORT:-3333}"
    if ! check_port_listening "$VERIFIER_PORT"; then
        log_and_echo "❌ ERROR: Verifier is not listening on port $VERIFIER_PORT"
        log_and_echo "   Verifier PID: $VERIFIER_PID"
        log_and_echo "   Process exists but port is not accessible"
        log_and_echo "   Check logs: ${VERIFIER_LOG:-<not set>}"
        exit 1
    fi
    
    # Check verifier health endpoint
    if ! check_verifier_health "$VERIFIER_PORT"; then
        log_and_echo "❌ ERROR: Verifier health check failed"
        log_and_echo "   Verifier PID: $VERIFIER_PID"
        log_and_echo "   Port $VERIFIER_PORT is listening but /health endpoint failed"
        log_and_echo "   Check logs: ${VERIFIER_LOG:-<not set>}"
        exit 1
    fi
    log "   ✅ Verifier is running and healthy (PID: $VERIFIER_PID, port: $VERIFIER_PORT)"
}

# Verify solver is running
# Usage: verify_solver_running
# Checks solver process
# Exits with error if solver is not running
verify_solver_running() {
    # Ensure LOG_DIR is set (for reading PID files)
    if [ -z "$LOG_DIR" ] && [ -n "$PROJECT_ROOT" ]; then
        LOG_DIR="$PROJECT_ROOT/.tmp/e2e-tests"
    fi
    
    log ""
    log "🔍 Verifying solver is running..."
    
    # Try to load SOLVER_PID from file if not set
    if [ -z "$SOLVER_PID" ] && [ -n "$LOG_DIR" ] && [ -f "$LOG_DIR/solver.pid" ]; then
        SOLVER_PID=$(cat "$LOG_DIR/solver.pid" 2>/dev/null || echo "")
        export SOLVER_PID
    fi
    
    # Check solver
    if [ -z "$SOLVER_PID" ] || ! ps -p "$SOLVER_PID" > /dev/null 2>&1; then
        log_and_echo "❌ ERROR: Solver is not running"
        log_and_echo "   Expected PID: ${SOLVER_PID:-<not set>}"
        log_and_echo "   Please start solver first using start-solver.sh"
        exit 1
    fi
    log "   ✅ Solver is running (PID: $SOLVER_PID)"
}

# Note: verify_solver_registered() is defined in util_mvm.sh with auto-detection
# Both MVM and EVM E2E tests source util_mvm.sh since the hub chain is always MVM

# Display solver and verifier logs for debugging
# Usage: display_service_logs [context_message]
# Shows last 100 lines of solver.log and verifier.log if they exist
display_service_logs() {
    local context="${1:-Error occurred}"
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    local log_dir="$PROJECT_ROOT/.tmp/e2e-tests"
    local solver_log="$log_dir/solver.log"
    local verifier_log="$log_dir/verifier.log"
    
    # Get current timestamp in ISO format (matches Rust log format)
    local error_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log_and_echo ""
    log_and_echo "📋 Service Logs ($context)"
    log_and_echo "=========================================="
    log_and_echo "⏰ Error occurred at: $error_timestamp"
    log_and_echo ""
    
    if [ -f "$verifier_log" ]; then
        log_and_echo ""
        log_and_echo "🔍 Verifier logs (last 100 lines):"
        log_and_echo "-----------------------------------"
        tail -100 "$verifier_log" | sed 's/^/   /'
    else
        log_and_echo ""
        log_and_echo "⚠️  Verifier log not found: $verifier_log"
    fi
    
    if [ -f "$solver_log" ]; then
        log_and_echo ""
        log_and_echo "🔍 Solver logs (last 100 lines):"
        log_and_echo "-----------------------------------"
        tail -100 "$solver_log" | sed 's/^/   /'
    else
        log_and_echo ""
        log_and_echo "⚠️  Solver log not found: $solver_log"
    fi
    
    log_and_echo ""
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
        export VERIFIER_CONFIG_PATH="$PROJECT_ROOT/trusted-verifier/config/verifier-e2e-ci-testing.toml"
    fi
    
    # Load keys
    load_verifier_keys

    local log_file="${1:-$LOG_DIR/verifier.log}"
    local rust_log="${2:-info}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"
    
    # Delete existing log file to start fresh for this test run
    if [ -f "$log_file" ]; then
        rm -f "$log_file"
    fi
    
    # Stop any existing verifier first
    stop_verifier
    
    log "   Starting verifier service..."
    log "   Using config: $VERIFIER_CONFIG_PATH"
    log "   Log file: $log_file"
    
    # Use pre-built binary (must be built first via Step 0)
    local verifier_binary="$PROJECT_ROOT/trusted-verifier/target/debug/trusted-verifier"
    if [ ! -f "$verifier_binary" ]; then
        log_and_echo "   ❌ PANIC: Verifier binary not found: $verifier_binary"
        log_and_echo "   Please build first: cd trusted-verifier && cargo build --bin trusted-verifier"
        exit 1
    fi
    
    log "   Using binary: $verifier_binary"
    VERIFIER_CONFIG_PATH="$VERIFIER_CONFIG_PATH" RUST_LOG="$rust_log" "$verifier_binary" >> "$log_file" 2>&1 &
    VERIFIER_PID=$!
    
    # Export PID so it persists across subshells
    export VERIFIER_PID
    
    # Save PID to file for cross-script persistence
    if [ -n "$LOG_DIR" ]; then
        echo "$VERIFIER_PID" > "$LOG_DIR/verifier.pid"
    fi
    
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

# Stop solver processes
# Usage: stop_solver
# Stops any running solver processes
stop_solver() {
    log "   Checking for existing solvers..."
    
    if pgrep -f "cargo.*solver" > /dev/null || pgrep -f "target/debug/solver" > /dev/null; then
        log "   ⚠️  Found existing solver processes, stopping them..."
        pkill -f "cargo.*solver" || true
        pkill -f "target/debug/solver" || true
        sleep 2
        log "   ✅ Solver processes stopped"
    else
        log "   ✅ No existing solver processes"
    fi
}

# Check solver health (placeholder - solver service doesn't have health endpoint yet)
# Usage: check_solver_health [port]
# Returns 0 if healthy, 1 if not
# TODO: Implement health check once solver service has health endpoint
check_solver_health() {
    # Placeholder - solver service will have health endpoint in future
    # For now, just check if process is running
    local port="${1:-3334}"
    
    # TODO: Once solver service is implemented, check health endpoint
    # if curl -s -f "http://127.0.0.1:${port}/health" > /dev/null 2>&1; then
    #     return 0
    # else
    #     return 1
    # fi
    
    # For now, return 1 (not implemented)
    return 1
}


# Start solver service
# Usage: start_solver [log_file] [rust_log_level] [config_path]
# Starts solver in background and waits for it to be ready
# Sets SOLVER_PID and SOLVER_LOG global variables
# Exits with error if solver fails to start
# NOTE: This will fail until solver service is implemented (Task 6-7)
start_solver() {
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    local log_file="${1:-$LOG_DIR/solver.log}"
    local rust_log="${2:-info}"
    local config_path="${3:-$PROJECT_ROOT/solver/config/solver.toml}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"
    
    # Delete existing log file to start fresh for this test run
    if [ -f "$log_file" ]; then
        rm -f "$log_file"
    fi
    
    # Stop any existing solver first
    stop_solver
    
    log "   Starting solver service..."
    log "   Using config: $config_path"
    log "   Log file: $log_file"
    
    # Use pre-built binary (must be built first via Step 0)
    local solver_binary="$PROJECT_ROOT/solver/target/debug/solver"
    if [ ! -f "$solver_binary" ]; then
        log_and_echo "   ❌ PANIC: Solver binary not found: $solver_binary"
        log_and_echo "   Please build first: cd solver && cargo build --bin solver"
        exit 1
    fi
    
    log "   Using binary: $solver_binary"
    SOLVER_CONFIG_PATH="$config_path" RUST_LOG="$rust_log" "$solver_binary" >> "$log_file" 2>&1 &
    SOLVER_PID=$!
    
    # Export PID so it persists across subshells
    export SOLVER_PID
    
    # Save PID to file for cross-script persistence
    if [ -n "$LOG_DIR" ]; then
        echo "$SOLVER_PID" > "$LOG_DIR/solver.pid"
    fi
    
    log "   ✅ Solver started with PID: $SOLVER_PID"
    
    # Wait for solver to be ready (check for "Starting all services" in log)
    # This properly waits for compilation + initialization in CI
    log "   - Waiting for solver to initialize (may take a while if compiling)..."
    RETRY_COUNT=0
    MAX_RETRIES=180  # 3 minutes to allow for compilation in CI
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Check if process is still running
        if ! ps -p "$SOLVER_PID" > /dev/null 2>&1; then
            log_and_echo "   ❌ Solver process died"
            log_and_echo "   Solver log:"
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
            if [ -f "$log_file" ]; then
                cat "$log_file" | while read line; do log_and_echo "   $line"; done
            else
                log_and_echo "   Log file not found at: $log_file"
            fi
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
            exit 1
        fi
        
        # Check if solver has initialized by looking for the startup log message
        if [ -f "$log_file" ] && grep -q "Starting all services" "$log_file" 2>/dev/null; then
            log "   ✅ Solver is ready!"
            SOLVER_LOG="$log_file"
            export SOLVER_PID SOLVER_LOG
            return 0
        fi
        
        # Show progress every 10 seconds
        if [ $((RETRY_COUNT % 10)) -eq 0 ] && [ $RETRY_COUNT -gt 0 ]; then
            if [ -f "$log_file" ]; then
                # Show last line of log to indicate progress
                local last_line=$(tail -1 "$log_file" 2>/dev/null || echo "")
                if [ -n "$last_line" ]; then
                    log "   ... still waiting (${RETRY_COUNT}s): $last_line"
                fi
            fi
        fi
        
        sleep 1
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    
    # If we get here, solver didn't become ready
    log_and_echo "   ❌ Solver failed to start after $MAX_RETRIES seconds"
    log_and_echo "   Solver log:"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    if [ -f "$log_file" ]; then
        log_and_echo "   $(cat "$log_file")"
    else
        log_and_echo "   Log file not found at: $log_file"
    fi
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
}

# ============================================================================
# VERIFIER NEGOTIATION ROUTING HELPERS
# ============================================================================

# Get verifier API base URL
# Usage: get_verifier_url [port]
# Returns the base URL for verifier API calls
get_verifier_url() {
    local port="${1:-3333}"
    echo "http://127.0.0.1:${port}"
}

# Submit draft intent to verifier
# Usage: submit_draft_intent <requester_address> <draft_data_json> <expiry_time> [verifier_port]
# Returns the draft_id on success, exits on error
# draft_data_json should be a JSON object with intent details
# Note: Cannot use log/log_and_echo for success path because this function's output
# is captured via command substitution, and log functions write to stdout.
submit_draft_intent() {
    local requester_address="$1"
    local draft_data_json="$2"
    local expiry_time="$3"
    local verifier_port="${4:-3333}"
    
    if [ -z "$requester_address" ] || [ -z "$draft_data_json" ] || [ -z "$expiry_time" ]; then
        log_and_echo "❌ ERROR: submit_draft_intent() requires requester_address, draft_data_json, and expiry_time"
        exit 1
    fi
    
    local verifier_url=$(get_verifier_url "$verifier_port")
    
    # Log to stderr so it doesn't contaminate the return value
    echo "   Submitting draft intent to verifier..." >&2
    echo "     Requester: $requester_address" >&2
    [ -n "$LOG_FILE" ] && echo "   Submitting draft intent to verifier..." >> "$LOG_FILE"
    [ -n "$LOG_FILE" ] && echo "     Requester: $requester_address" >> "$LOG_FILE"
    
    # Build request body using jq to ensure valid JSON
    local request_body
    request_body=$(jq -n \
        --arg ra "$requester_address" \
        --argjson dd "$draft_data_json" \
        --argjson et "$expiry_time" \
        '{
            requester_address: $ra,
            draft_data: $dd,
            expiry_time: $et
        }')
    
    # Log the request for debugging (to stderr)
    echo "     DEBUG: Request body:" >&2
    echo "$request_body" >&2
    [ -n "$LOG_FILE" ] && echo "     DEBUG: Request body:" >> "$LOG_FILE"
    [ -n "$LOG_FILE" ] && echo "$request_body" >> "$LOG_FILE"
    
    local response
    response=$(curl -s -X POST "${verifier_url}/draftintent" \
        -H "Content-Type: application/json" \
        -d "$request_body" 2>&1)
    
    local curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_and_echo "❌ ERROR: Failed to connect to verifier at ${verifier_url}"
        log_and_echo "   curl exit code: $curl_exit"
        exit 1
    fi
    
    # Check for success
    local success=$(echo "$response" | jq -r '.success // false')
    if [ "$success" != "true" ]; then
        local error=$(echo "$response" | jq -r '.error // "Unknown error"')
        log_and_echo "❌ ERROR: Failed to submit draft intent"
        log_and_echo "   Error: $error"
        log_and_echo "   Response: $response"
        exit 1
    fi
    
    local draft_id=$(echo "$response" | jq -r '.data.draft_id')
    if [ -z "$draft_id" ] || [ "$draft_id" = "null" ]; then
        log_and_echo "❌ ERROR: No draft_id in response"
        log_and_echo "   Response: $response"
        exit 1
    fi
    
    # Log to stderr so it doesn't contaminate the return value (stdout is captured by caller)
    echo "     ✅ Draft submitted with ID: $draft_id" >&2
    [ -n "$LOG_FILE" ] && echo "     ✅ Draft submitted with ID: $draft_id" >> "$LOG_FILE"
    echo "$draft_id"
}

# Poll verifier for pending drafts (solver perspective)
# Usage: poll_pending_drafts [verifier_port]
# Returns JSON array of pending drafts
# Note: Cannot use log/log_and_echo for success path because this function's output
# is captured via command substitution (e.g., PENDING_DRAFTS=$(poll_pending_drafts)),
# and log functions write to stdout which would contaminate the JSON output.
poll_pending_drafts() {
    local verifier_port="${1:-3333}"
    local verifier_url=$(get_verifier_url "$verifier_port")
    
    local response
    response=$(curl -s -X GET "${verifier_url}/draftintents/pending" 2>&1)
    
    local curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_and_echo "❌ ERROR: Failed to connect to verifier at ${verifier_url}"
        exit 1
    fi
    
    local success=$(echo "$response" | jq -r '.success // false')
    if [ "$success" != "true" ]; then
        local error=$(echo "$response" | jq -r '.error // "Unknown error"')
        log_and_echo "❌ ERROR: Failed to poll pending drafts"
        log_and_echo "   Error: $error"
        exit 1
    fi
    
    local drafts=$(echo "$response" | jq -r '.data')
    echo "$drafts"
}

# Get draft intent by ID
# Usage: get_draft_intent <draft_id> [verifier_port]
# Returns the draft data JSON
get_draft_intent() {
    local draft_id="$1"
    local verifier_port="${2:-3333}"
    
    if [ -z "$draft_id" ]; then
        log_and_echo "❌ ERROR: get_draft_intent() requires draft_id"
        exit 1
    fi
    
    local verifier_url=$(get_verifier_url "$verifier_port")
    
    local response
    response=$(curl -s -X GET "${verifier_url}/draftintent/${draft_id}" 2>&1)
    
    local curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_and_echo "❌ ERROR: Failed to connect to verifier at ${verifier_url}"
        exit 1
    fi
    
    local success=$(echo "$response" | jq -r '.success // false')
    if [ "$success" != "true" ]; then
        local error=$(echo "$response" | jq -r '.error // "Unknown error"')
        log_and_echo "❌ ERROR: Failed to get draft intent"
        log_and_echo "   Error: $error"
        exit 1
    fi
    
    echo "$response" | jq -r '.data'
}

# Submit signature to verifier (solver submits after signing)
# Usage: submit_signature_to_verifier <draft_id> <solver_address> <signature_hex> <public_key_hex> [verifier_port]
# Returns success/failure, exits on error
submit_signature_to_verifier() {
    local draft_id="$1"
    local solver_address="$2"
    local signature_hex="$3"
    local public_key_hex="$4"
    local verifier_port="${5:-3333}"
    
    if [ -z "$draft_id" ] || [ -z "$solver_address" ] || [ -z "$signature_hex" ] || [ -z "$public_key_hex" ]; then
        log_and_echo "❌ ERROR: submit_signature_to_verifier() requires draft_id, solver_address, signature_hex, public_key_hex"
        exit 1
    fi
    
    # Normalize solver address: ensure 0x prefix (aptos config returns addresses without prefix)
    local normalized_solver_address
    if [ "${solver_address#0x}" != "$solver_address" ]; then
        # Already has 0x prefix
        normalized_solver_address="$solver_address"
    else
        # Add 0x prefix
        normalized_solver_address="0x$solver_address"
    fi
    
    local verifier_url=$(get_verifier_url "$verifier_port")
    
    log "   Submitting signature to verifier..."
    log "     Draft ID: $draft_id"
    log "     Solver: $normalized_solver_address"
    
    local response
    response=$(curl -s -X POST "${verifier_url}/draftintent/${draft_id}/signature" \
        -H "Content-Type: application/json" \
        -d "{
            \"solver_address\": \"$normalized_solver_address\",
            \"signature\": \"$signature_hex\",
            \"public_key\": \"$public_key_hex\"
        }" 2>&1)
    
    local curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_and_echo "❌ ERROR: Failed to connect to verifier at ${verifier_url}"
        exit 1
    fi
    
    local success=$(echo "$response" | jq -r '.success // false')
    if [ "$success" != "true" ]; then
        local error=$(echo "$response" | jq -r '.error // "Unknown error"')
        # Check if it's a 409 Conflict (already signed)
        if echo "$error" | grep -qi "already signed\|conflict"; then
            log "     ⚠️  Draft already signed by another solver (FCFS)"
            return 1
        fi
        log_and_echo "❌ ERROR: Failed to submit signature"
        log_and_echo "   Error: $error"
        log_and_echo "   Response: $response"
        exit 1
    fi
    
    log "     ✅ Signature submitted successfully"
    return 0
}

# Poll verifier for signature (requester polls after submitting draft)
# Usage: poll_for_signature <draft_id> [max_attempts] [sleep_seconds] [verifier_port]
# Returns signature JSON on success, exits on timeout
poll_for_signature() {
    local draft_id="$1"
    local max_attempts="${2:-60}"
    local sleep_seconds="${3:-2}"
    local verifier_port="${4:-3333}"
    
    if [ -z "$draft_id" ]; then
        log_and_echo "❌ ERROR: poll_for_signature() requires draft_id"
        exit 1
    fi
    
    local verifier_url=$(get_verifier_url "$verifier_port")
    
    # Use >&2 for all logs to avoid capturing them in command substitution
    echo "   Polling verifier for signature..." >&2
    echo "     Draft ID: $draft_id" >&2
    echo "     Max attempts: $max_attempts, interval: ${sleep_seconds}s" >&2
    [ -n "$LOG_FILE" ] && echo "   Polling verifier for signature..." >> "$LOG_FILE"
    [ -n "$LOG_FILE" ] && echo "     Draft ID: $draft_id" >> "$LOG_FILE"
    [ -n "$LOG_FILE" ] && echo "     Max attempts: $max_attempts, interval: ${sleep_seconds}s" >> "$LOG_FILE"
    
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local response
        response=$(curl -s -X GET "${verifier_url}/draftintent/${draft_id}/signature" 2>/dev/null)
        
        local curl_exit=$?
        if [ $curl_exit -ne 0 ] || [ -z "$response" ]; then
            echo "     Attempt $((attempt+1)): Connection failed, retrying..." >&2
            [ -n "$LOG_FILE" ] && echo "     Attempt $((attempt+1)): Connection failed, retrying..." >> "$LOG_FILE"
            sleep "$sleep_seconds"
            attempt=$((attempt + 1))
            continue
        fi
        
        # Debug: show response
        echo "     Attempt $((attempt+1)): Response: $response" >&2
        [ -n "$LOG_FILE" ] && echo "     Attempt $((attempt+1)): Response: $response" >> "$LOG_FILE"
        
        local success=$(echo "$response" | jq -r '.success // false' 2>/dev/null)
        if [ "$success" = "true" ]; then
            local signature=$(echo "$response" | jq -r '.data.signature // empty' 2>/dev/null)
            local solver=$(echo "$response" | jq -r '.data.solver_address // empty' 2>/dev/null)
            
            if [ -n "$signature" ] && [ "$signature" != "null" ]; then
                echo "     ✅ Signature received from solver: $solver" >&2
                [ -n "$LOG_FILE" ] && echo "     ✅ Signature received from solver: $solver" >> "$LOG_FILE"
                echo "$response" | jq -r '.data'
                return 0
            fi
        fi
        
        sleep "$sleep_seconds"
        attempt=$((attempt + 1))
    done
    
    # Return empty on timeout instead of exiting (let caller handle)
    echo ""
    return 1
}

# Build draft data JSON for intent
# Usage: build_draft_data <offered_metadata> <offered_amount> <offered_chain_id> <desired_metadata> <desired_amount> <desired_chain_id> <expiry_time> <intent_id> <issuer> [extra_fields_json]
# Returns JSON object suitable for submit_draft_intent
build_draft_data() {
    local offered_metadata="$1"
    local offered_amount="$2"
    local offered_chain_id="$3"
    local desired_metadata="$4"
    local desired_amount="$5"
    local desired_chain_id="$6"
    local expiry_time="$7"
    local intent_id="$8"
    local issuer="$9"
    local extra_fields="${10:-{}}"
    
    # Validate extra_fields is valid JSON, default to {} if not
    local validated_extra
    if ! validated_extra=$(echo "$extra_fields" | jq . 2>/dev/null); then
        # Redirect warning to stderr so it doesn't contaminate JSON output
        echo "   Warning: extra_fields is not valid JSON, using empty object" >&2
        [ -n "$LOG_FILE" ] && echo "   Warning: extra_fields is not valid JSON, using empty object" >> "$LOG_FILE"
        validated_extra="{}"
    fi
    
    # Build the JSON object (redirect any warnings to stderr)
    local json
    json=$(jq -n \
        --arg om "$offered_metadata" \
        --arg oa "$offered_amount" \
        --arg oci "$offered_chain_id" \
        --arg dm "$desired_metadata" \
        --arg da "$desired_amount" \
        --arg dci "$desired_chain_id" \
        --arg et "$expiry_time" \
        --arg ii "$intent_id" \
        --arg is "$issuer" \
        --argjson extra "$validated_extra" \
        '{
            offered_metadata: $om,
            offered_amount: $oa,
            offered_chain_id: $oci,
            desired_metadata: $dm,
            desired_amount: $da,
            desired_chain_id: $dci,
            expiry_time: $et,
            intent_id: $ii,
            issuer: $is
        } + $extra' 2>&1)
    
    local jq_exit=$?
    if [ $jq_exit -ne 0 ]; then
        log "   ERROR: build_draft_data jq failed with exit code $jq_exit"
        log "   jq output: $json"
        log "   Inputs: om=$offered_metadata, oa=$offered_amount, oci=$offered_chain_id"
        log "   Inputs: dm=$desired_metadata, da=$desired_amount, dci=$desired_chain_id"
        log "   Inputs: et=$expiry_time, ii=$intent_id, is=$issuer"
        log "   Inputs: extra=$validated_extra"
        echo "{}"
        return 1
    fi
    
    echo "$json"
}

# Wait for solver to automatically fulfill an intent
# Polls the verifier's /events endpoint for fulfillment events matching the intent
# Usage: wait_for_solver_fulfillment <intent_id> <flow_type> [timeout_seconds]
#   intent_id: The intent ID to wait for
#   flow_type: "inflow" or "outflow"
#   timeout_seconds: Maximum wait time (default: 60)
# Returns: 0 on success, 1 on timeout
wait_for_solver_fulfillment() {
    local intent_id="$1"
    local flow_type="$2"
    local timeout_seconds="${3:-60}"
    local poll_interval=3
    local elapsed=0
    
    local verifier_url="${VERIFIER_URL:-http://127.0.0.1:3333}"
    
    log ""
    log "⏳ Waiting for solver to automatically fulfill $flow_type intent..."
    log "   Intent ID: $intent_id"
    log "   Timeout: ${timeout_seconds}s (polling every ${poll_interval}s)"
    log "   The solver service should detect the escrow/intent and fulfill automatically."
    log ""
    
    # Normalize intent_id for comparison (remove 0x prefix and leading zeros)
    local normalized_intent_id
    normalized_intent_id=$(echo "$intent_id" | tr '[:upper:]' '[:lower:]' | sed 's/^0x//' | sed 's/^0*//')
    
    local solver_log_file="${LOG_DIR:-$PROJECT_ROOT/.tmp/e2e-tests}/solver.log"
    
    while [ $elapsed -lt $timeout_seconds ]; do
        # Check for fulfillment event in verifier (works for inflow)
        local events_response
        events_response=$(curl -s "${verifier_url}/events" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            # Check if fulfillment event exists for this intent
            local fulfillment_found
            fulfillment_found=$(echo "$events_response" | jq -r --arg nid "$normalized_intent_id" \
                '.data.fulfillment_events[]? | select(.intent_id | ascii_downcase | gsub("^0x"; "") | gsub("^0+"; "") == $nid) | .intent_id' \
                2>/dev/null | head -1)
            
            if [ -n "$fulfillment_found" ]; then
                log "   ✅ Solver fulfilled the intent! (detected via verifier after ${elapsed}s)"
                log "   Fulfillment event found for intent: $fulfillment_found"
                return 0
            fi
        fi
        
        # Also check solver logs for successful fulfillment (works for outflow)
        # Note: fa_intent_with_oracle doesn't emit LimitOrderFulfillmentEvent, so we check solver logs
        # Use normalized_intent_id (without leading zeros) since solver logs may strip them
        if [ -f "$solver_log_file" ]; then
            # Search for intent ID with or without leading zeros (0xd86... or 0x000d86...)
            local intent_id_no_zeros="0x${normalized_intent_id}"
            if grep -qi "Successfully fulfilled.*${intent_id_no_zeros}" "$solver_log_file" 2>/dev/null; then
                log "   ✅ Solver fulfilled the intent! (detected via solver logs after ${elapsed}s)"
                return 0
            fi
        fi
        
        printf "   Waiting for solver... (%ds/%ds)\r" $elapsed $timeout_seconds
        sleep $poll_interval
        elapsed=$((elapsed + poll_interval))
    done
    
    # Timeout - show diagnostic info
    log ""
    log_and_echo "⏰ Timeout waiting for solver fulfillment after ${timeout_seconds}s"
    log ""
    log "🔍 Diagnostic Information:"
    log "========================================"
    
    # Show solver logs (solver_log_file already declared above)
    if [ -f "$solver_log_file" ]; then
        log ""
        log "   Solver logs (last 100 lines):"
        log "   + + + + + + + + + + + + + + + + + + + +"
        tail -100 "$solver_log_file" | while IFS= read -r line; do log "   $line"; done
        log "   + + + + + + + + + + + + + + + + + + + +"
    else
        log "   Solver log file not found at: $solver_log_file"
    fi
    
    # Show verifier logs
    local verifier_log_file="${LOG_DIR:-$PROJECT_ROOT/.tmp/e2e-tests}/verifier.log"
    if [ -f "$verifier_log_file" ]; then
        log ""
        log "   Verifier logs (last 100 lines):"
        log "   + + + + + + + + + + + + + + + + + + + +"
        tail -100 "$verifier_log_file" | while IFS= read -r line; do log "   $line"; done
        log "   + + + + + + + + + + + + + + + + + + + +"
    else
        log ""
        log "   Verifier log file not found (checked: $verifier_log_file)"
    fi
    
    # Show verifier events
    log ""
    log "   Verifier events:"
    local events_response
    events_response=$(curl -s "${verifier_url}/events" 2>/dev/null)
    if [ $? -eq 0 ]; then
        local escrow_count fulfillment_count intent_count
        escrow_count=$(echo "$events_response" | jq -r '.data.escrow_events | length' 2>/dev/null || echo "0")
        fulfillment_count=$(echo "$events_response" | jq -r '.data.fulfillment_events | length' 2>/dev/null || echo "0")
        intent_count=$(echo "$events_response" | jq -r '.data.intent_events | length' 2>/dev/null || echo "0")
        
        log "      Intent events: $intent_count"
        log "      Escrow events: $escrow_count"
        log "      Fulfillment events: $fulfillment_count"
        
        if [ "$escrow_count" != "0" ]; then
            log ""
            log "      Escrow details:"
            echo "$events_response" | jq -r '.data.escrow_events[] | "         \(.intent_id) - amount: \(.offered_amount)"' 2>/dev/null || log "         (parse error)"
        fi
    else
        log "      Failed to query verifier events"
    fi
    
    return 1
}

