#!/bin/bash

# EVM-specific utilities for testing infrastructure scripts
# This file MUST be sourced AFTER util.sh
# Usage: 
#   source "$(dirname "$0")/../util.sh"
#   source "$(dirname "$0")/../util_evm.sh"
#
# Note: This file depends on functions from util.sh (log, log_and_echo, setup_project_root, etc.)

# Get USDxyz balance for an EVM account
# Usage: get_usdxyz_balance_evm <account_address> <usdxyz_token_address>
# Returns the USDxyz balance for the given account
# PANICS if inputs are missing or balance lookup fails
get_usdxyz_balance_evm() {
    local account="$1"
    local token_address="$2"
    
    # Validate inputs
    if [ -z "$account" ] || [ -z "$token_address" ]; then
        echo "❌ PANIC: get_usdxyz_balance_evm requires account and token_address" >&2
        echo "   account: '$account', token_address: '$token_address'" >&2
        exit 1
    fi
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    local balance_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$token_address' ACCOUNT='$account' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1)
    local balance=$(echo "$balance_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
    
    if [ -z "$balance" ]; then
        echo "❌ PANIC: get_usdxyz_balance_evm failed to get balance" >&2
        echo "   account: $account, token_address: $token_address" >&2
        echo "   output: $balance_output" >&2
        exit 1
    fi
    
    echo "$balance"
}

# Display balances for Chain 3 (Connected EVM)
# Usage: display_balances_connected_evm [usdxyz_token_address]
# Fetches and displays Requester and Solver balances on the Connected EVM chain
# If usdxyz_token_address is provided, also displays USDxyz balances
# Only displays if EVM chain is running (skips silently if it's not)
display_balances_connected_evm() {
    local usdxyz_addr="$1"
    
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
    # Account 0 = deployer, Account 1 = Requester, Account 2 = Solver
    local requester_evm_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
    local requester_evm=$(echo "$requester_evm_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
    
    local solver_evm_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
    local solver_evm=$(echo "$solver_evm_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
    
    # Get account addresses for USDxyz balance lookup
    local requester_addr=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1)
    local solver_addr=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1)
    
    cd "$PROJECT_ROOT"
    
    log_and_echo "   Chain 3 (Connected EVM):"
    
    # Format EVM balances
    local requester_eth="0"
    local solver_eth="0"
    
    if [ "$requester_evm" != "0" ] && [ -n "$requester_evm" ]; then
        requester_eth=$(echo "scale=4; $requester_evm / 1000000000000000000" | bc 2>/dev/null || echo "N/A")
    fi
    
    if [ "$solver_evm" != "0" ] && [ -n "$solver_evm" ]; then
        solver_eth=$(echo "scale=4; $solver_evm / 1000000000000000000" | bc 2>/dev/null || echo "N/A")
    fi
    
    if [ -n "$usdxyz_addr" ]; then
        # PANIC if we passed a token address but couldn't get account addresses
        if [ -z "$requester_addr" ] || [ -z "$solver_addr" ]; then
            log_and_echo "❌ PANIC: display_balances_connected_evm failed to get account addresses"
            log_and_echo "   requester_addr: '$requester_addr'"
            log_and_echo "   solver_addr: '$solver_addr'"
            exit 1
        fi
        
        local requester_usdxyz=$(get_usdxyz_balance_evm "$requester_addr" "$usdxyz_addr")
        local solver_usdxyz=$(get_usdxyz_balance_evm "$solver_addr" "$usdxyz_addr")
        
        # PANIC if we passed a token address but couldn't get balances
        if [ -z "$requester_usdxyz" ] || [ -z "$solver_usdxyz" ]; then
            log_and_echo "❌ PANIC: display_balances_connected_evm failed to get USDxyz balances"
            log_and_echo "   usdxyz_addr: $usdxyz_addr"
            log_and_echo "   requester_usdxyz: '$requester_usdxyz'"
            log_and_echo "   solver_usdxyz: '$solver_usdxyz'"
            exit 1
        fi
        
        log_and_echo "      Requester (Acc 1): ${requester_eth} ETH, $requester_usdxyz USDxyz"
        log_and_echo "      Solver (Acc 2): ${solver_eth} ETH, $solver_usdxyz USDxyz"
    else
        log_and_echo "      Requester (Acc 1): ${requester_eth} ETH"
        log_and_echo "      Solver (Acc 2): ${solver_eth} ETH"
    fi
}
