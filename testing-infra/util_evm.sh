#!/bin/bash

# EVM-specific utilities for testing infrastructure scripts
# This file MUST be sourced AFTER util.sh
# Usage: 
#   source "$(dirname "$0")/../util.sh"
#   source "$(dirname "$0")/../util_evm.sh"
#
# Note: This file depends on functions from util.sh (log, log_and_echo, setup_project_root, etc.)

# Display balances for Chain 3 (Connected EVM)
# Usage: display_balances_connected_evm
# Fetches and displays Alice and Bob balances on the Connected EVM chain
# Only displays if EVM chain is running (skips silently if it's not)
display_balances_connected_evm() {
    # Check if EVM chain is running
    if ! curl -s -X POST http://127.0.0.1:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        >/dev/null 2>&1; then
        return 0  # Silently skip if EVM chain is not running
    fi
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    cd "$PROJECT_ROOT/evm-intent-framework"
    
    # Use the actual script files instead of inline heredoc (Hardhat doesn't support inline scripts)
    # Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
    local alice_evm_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
    local alice_evm=$(echo "$alice_evm_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
    
    local solver_evm_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
    local solver_evm=$(echo "$solver_evm_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
    
    cd "$PROJECT_ROOT"
    
    log_and_echo "   Chain 3 (Connected EVM):"
    
    # Format EVM balances (show both ETH and wei)
    if [ "$alice_evm" != "0" ] && [ -n "$alice_evm" ]; then
        local alice_eth=$(echo "scale=4; $alice_evm / 1000000000000000000" | bc 2>/dev/null || echo "N/A")
        log_and_echo "      Alice (Acc 1): ${alice_eth} ETH"
    else
        log_and_echo "      Alice (Acc 1): 0 ETH"
    fi
    
    if [ "$solver_evm" != "0" ] && [ -n "$solver_evm" ]; then
        local bob_eth=$(echo "scale=4; $solver_evm / 1000000000000000000" | bc 2>/dev/null || echo "N/A")
        log_and_echo "      Bob (Acc 2): ${bob_eth} ETH"
    else
        log_and_echo "      Bob (Acc 2): 0 ETH"
    fi
}

