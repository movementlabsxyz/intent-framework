#!/bin/bash

# Start Solver Service for E2E Tests (EVM Connected Chain)
# 
# This script generates a solver configuration for EVM connected chain tests
# and starts the solver service.
#
# Required environment variables (set by run-tests-*.sh):
# - CHAIN1_URL: Hub chain RPC URL (Move VM)
# - EVM_RPC_URL: Connected chain RPC URL (EVM)
# - CHAIN1_ID: Hub chain ID
# - EVM_CHAIN_ID: Connected EVM chain ID
# - ACCOUNT_ADDRESS: Hub chain module address
# - ESCROW_CONTRACT_ADDRESS: EVM escrow contract address
# - EVM_PRIVATE_KEY_ENV: Environment variable name for EVM private key

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"

# Setup project root and logging
setup_project_root
setup_logging "solver-start-evm"
cd "$PROJECT_ROOT"

log ""
log "🚀 Starting Solver Service (EVM Connected Chain)..."
log "========================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

# Generate solver config for EVM E2E tests
generate_solver_config_evm() {
    local config_file="$1"
    
    # Use environment variables from test setup
    local verifier_url="${VERIFIER_URL:-http://127.0.0.1:3333}"
    local hub_rpc="${CHAIN1_URL:-http://127.0.0.1:8080/v1}"
    local evm_rpc="${EVM_RPC_URL:-http://127.0.0.1:8545}"
    local hub_chain_id="${CHAIN1_ID:-1}"
    local evm_chain_id="${EVM_CHAIN_ID:-31337}"
    local module_address="${ACCOUNT_ADDRESS:-0x123}"
    local escrow_contract="${ESCROW_CONTRACT_ADDRESS:-0x0}"
    local solver_address="${SOLVER_ADDRESS:-$module_address}"
    local evm_private_key_env="${EVM_PRIVATE_KEY_ENV:-SOLVER_EVM_PRIVATE_KEY}"
    
    log "   Generating solver config:"
    log "   - Verifier URL: $verifier_url"
    log "   - Hub RPC: $hub_rpc (chain ID: $hub_chain_id)"
    log "   - EVM RPC: $evm_rpc (chain ID: $evm_chain_id)"
    log "   - Hub module address: $module_address"
    log "   - EVM escrow contract: $escrow_contract"
    log "   - Solver address: $solver_address"
    
    cat > "$config_file" << EOF
# Auto-generated solver config for EVM E2E tests
# Generated at: $(date)

[service]
verifier_url = "$verifier_url"
polling_interval_ms = 1000  # Poll frequently for tests

[hub_chain]
name = "Hub Chain (E2E Test)"
rpc_url = "$hub_rpc"
chain_id = $hub_chain_id
module_address = "$module_address"
profile = "default"

[connected_chain]
type = "evm"
name = "EVM Connected Chain (E2E Test)"
rpc_url = "$evm_rpc"
chain_id = $evm_chain_id
escrow_contract_address = "$escrow_contract"
private_key_env = "$evm_private_key_env"

[acceptance]
# Accept any token swap at 1:1 rate (for testing)
# In production, this would be configured with specific token pairs
"$hub_chain_id:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:$evm_chain_id:0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" = 1.0

[solver]
profile = "default"
address = "$solver_address"
EOF

    log "   ✅ Config written to: $config_file"
}

# Generate the config file
SOLVER_CONFIG="$PROJECT_ROOT/tmp/solver-e2e-evm.toml"
mkdir -p "$(dirname "$SOLVER_CONFIG")"
generate_solver_config_evm "$SOLVER_CONFIG"

# Start the solver service
if start_solver "$LOG_DIR/solver-evm.log" "info" "$SOLVER_CONFIG"; then
    log ""
    log_and_echo "✅ Solver started successfully"
    log_and_echo "   PID: $SOLVER_PID"
    log_and_echo "   Config: $SOLVER_CONFIG"
    log_and_echo "   Logs: $LOG_DIR/solver-evm.log"
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
        if start_solver "$LOG_DIR/solver-evm.log" "info" "$SOLVER_CONFIG"; then
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
