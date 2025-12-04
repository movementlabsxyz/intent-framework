#!/bin/bash

# Start Solver Service for E2E Tests
# 
# This script generates a solver configuration from aptos CLI profiles
# and starts the solver service.
#
# Optional environment variables:
# - CHAIN1_URL: Hub chain RPC URL (default: http://127.0.0.1:8080/v1)
# - CHAIN2_URL: Connected chain RPC URL (default: http://127.0.0.1:8082/v1)
# - CHAIN1_ID: Hub chain ID (default: 1)
# - CHAIN2_ID: Connected chain ID (default: 2)
# - VERIFIER_URL: Verifier URL (default: http://127.0.0.1:3333)

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "solver-start"
cd "$PROJECT_ROOT"

log ""
log "🚀 Starting Solver Service..."
log "========================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

# Generate solver config for MVM E2E tests
generate_solver_config_mvm() {
    local config_file="$1"
    
    # Get addresses from aptos CLI profiles (same as other test scripts)
    local chain1_address=$(get_profile_address "intent-account-chain1")
    local chain2_address=$(get_profile_address "intent-account-chain2")
    local solver_chain1_address=$(get_profile_address "solver-chain1")
    local test_tokens_chain1=$(get_profile_address "test-tokens-chain1")
    local test_tokens_chain2=$(get_profile_address "test-tokens-chain2")
    
    # Get USDxyz metadata addresses (for acceptance config)
    local usdxyz_metadata_chain1=$(get_usdxyz_metadata "0x${test_tokens_chain1}" "1")
    local usdxyz_metadata_chain2=$(get_usdxyz_metadata "0x${test_tokens_chain2}" "2")
    
    # Use environment variables or defaults for URLs
    local verifier_url="${VERIFIER_URL:-http://127.0.0.1:3333}"
    local hub_rpc="${CHAIN1_URL:-http://127.0.0.1:8080/v1}"
    local connected_rpc="${CHAIN2_URL:-http://127.0.0.1:8082/v1}"
    local hub_chain_id="${CHAIN1_ID:-1}"
    local connected_chain_id="${CHAIN2_ID:-2}"
    local hub_module_address="0x${chain1_address}"
    local connected_module_address="0x${chain2_address}"
    local solver_address="0x${solver_chain1_address}"
    
    log "   Generating solver config:"
    log "   - Verifier URL: $verifier_url"
    log "   - Hub RPC: $hub_rpc (chain ID: $hub_chain_id)"
    log "   - Connected RPC: $connected_rpc (chain ID: $connected_chain_id)"
    log "   - Hub module address: $hub_module_address"
    log "   - Connected module address: $connected_module_address"
    log "   - Solver address: $solver_address"
    log "   - USDxyz metadata chain 1: $usdxyz_metadata_chain1"
    log "   - USDxyz metadata chain 2: $usdxyz_metadata_chain2"
    
    cat > "$config_file" << EOF
# Auto-generated solver config for MVM E2E tests
# Generated at: $(date)

[service]
verifier_url = "$verifier_url"
polling_interval_ms = 1000  # Poll frequently for tests

[hub_chain]
name = "Hub Chain (E2E Test)"
rpc_url = "$hub_rpc"
chain_id = $hub_chain_id
module_address = "$hub_module_address"
profile = "solver-chain1"

[connected_chain]
type = "mvm"
name = "Connected Chain (E2E Test)"
rpc_url = "$connected_rpc"
chain_id = $connected_chain_id
module_address = "$connected_module_address"
profile = "solver-chain2"

[acceptance]
# Accept USDxyz swaps at 1:1 rate for E2E testing
# Inflow: offered on connected chain (2), desired on hub chain (1)
"$connected_chain_id:$usdxyz_metadata_chain2:$hub_chain_id:$usdxyz_metadata_chain1" = 1.0
# Outflow: offered on hub chain (1), desired on connected chain (2)
"$hub_chain_id:$usdxyz_metadata_chain1:$connected_chain_id:$usdxyz_metadata_chain2" = 1.0

[solver]
profile = "solver-chain1"
address = "$solver_address"
EOF

    log "   ✅ Config written to: $config_file"
}

# Generate the config file
SOLVER_CONFIG="$PROJECT_ROOT/.tmp/solver-e2e.toml"
mkdir -p "$(dirname "$SOLVER_CONFIG")"
generate_solver_config_mvm "$SOLVER_CONFIG"

# Start the solver service
if start_solver "$LOG_DIR/solver.log" "info" "$SOLVER_CONFIG"; then
    log ""
    log_and_echo "✅ Solver started successfully"
    log_and_echo "   PID: $SOLVER_PID"
    log_and_echo "   Config: $SOLVER_CONFIG"
    log_and_echo "   Logs: $LOG_DIR/solver.log"
else
    log ""
    log_and_echo "⚠️  Solver failed to start"
    log_and_echo "   Checking if binary needs to be built..."
    
    # Try building the solver
    log "   Building solver..."
    pushd "$PROJECT_ROOT/solver" > /dev/null
    if cargo build --bin solver 2>> "$LOG_FILE"; then
        log "   ✅ Solver built successfully"
        popd > /dev/null
        
        # Try starting again
        if start_solver "$LOG_DIR/solver.log" "info" "$SOLVER_CONFIG"; then
            log_and_echo "✅ Solver started successfully after build"
        else
            log_and_echo "❌ Solver still failed to start after build"
            exit 1
        fi
    else
        log_and_echo "❌ Failed to build solver"
        popd > /dev/null
        exit 1
    fi
fi
