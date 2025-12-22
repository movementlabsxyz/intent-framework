#!/bin/bash

# EVM-specific utilities for testing infrastructure scripts
# This file MUST be sourced AFTER util.sh
# Usage: 
#   source "$(dirname "$0")/../util.sh"
#   source "$(dirname "$0")/../util_evm.sh"
#
# Note: This file depends on functions from util.sh (log, log_and_echo, setup_project_root, etc.)

# Get USDcon balance for an EVM account
# Usage: get_usdcon_balance_evm <account_addr> <usd_token_addr>
# Returns the USDcon balance for the given account
# PANICS if inputs are missing or balance lookup fails
get_usdcon_balance_evm() {
    local account="$1"
    local token_addr="$2"
    
    # Validate inputs
    if [ -z "$account" ] || [ -z "$token_addr" ]; then
        echo "❌ PANIC: get_usdcon_balance_evm requires account and token_addr" >&2
        echo "   account: '$account', token_addr: '$token_addr'" >&2
        exit 1
    fi
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    local balance_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$token_addr' ACCOUNT='$account' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1)
    local balance=$(echo "$balance_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
    
    if [ -z "$balance" ]; then
        echo "❌ PANIC: get_usdcon_balance_evm failed to get balance" >&2
        echo "   account: $account, token_addr: $token_addr" >&2
        echo "   output: $balance_output" >&2
        exit 1
    fi
    
    echo "$balance"
}

# Display balances for Chain 3 (Connected EVM)
# Usage: display_balances_connected_evm [usdcon_token_addr]
# Fetches and displays Requester and Solver balances on the Connected EVM chain
# If usdcon_token_addr is provided, also displays USDcon balances
# Only displays if EVM chain is running (skips silently if it's not)
display_balances_connected_evm() {
    local usdcon_addr="$1"
    
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
    
    # Get account addresses for USDcon balance lookup
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
    
    if [ -n "$usdcon_addr" ]; then
        # PANIC if we passed a token address but couldn't get account addresses
        if [ -z "$requester_addr" ] || [ -z "$solver_addr" ]; then
            log_and_echo "❌ PANIC: display_balances_connected_evm failed to get account addresses"
            log_and_echo "   requester_addr: '$requester_addr'"
            log_and_echo "   solver_addr: '$solver_addr'"
            exit 1
        fi
        
        local requester_usdcon=$(get_usdcon_balance_evm "$requester_addr" "$usdcon_addr")
        local solver_usdcon=$(get_usdcon_balance_evm "$solver_addr" "$usdcon_addr")
        
        # PANIC if we passed a token address but couldn't get balances
        if [ -z "$requester_usdcon" ] || [ -z "$solver_usdcon" ]; then
            log_and_echo "❌ PANIC: display_balances_connected_evm failed to get USDcon balances"
            log_and_echo "   usdcon_addr: $usdcon_addr"
            log_and_echo "   requester_usdcon: '$requester_usdcon'"
            log_and_echo "   solver_usdcon: '$solver_usdcon'"
            exit 1
        fi
        
        log_and_echo "      Requester (Acc 1): ${requester_eth} ETH, $requester_usdcon 10e-6.USDcon"
        log_and_echo "      Solver (Acc 2): ${solver_eth} ETH, $solver_usdcon 10e-6.USDcon"
    else
        log_and_echo "      Requester (Acc 1): ${requester_eth} ETH"
        log_and_echo "      Solver (Acc 2): ${solver_eth} ETH"
    fi
}

# Check if an escrow is claimed
# Usage: is_escrow_claimed <escrow_addr> <intent_id_evm>
# Returns: "true" if claimed, "false" if not claimed, exits with error if check fails
is_escrow_claimed() {
    local escrow_addr="$1"
    local intent_id_evm="$2"
    
    if [ -z "$escrow_addr" ] || [ -z "$intent_id_evm" ]; then
        echo "❌ PANIC: is_escrow_claimed requires escrow_addr and intent_id_evm" >&2
        exit 1
    fi
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    local output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ESCROW_ADDRESS='$escrow_addr' INTENT_ID_EVM='$intent_id_evm' npx hardhat run scripts/get-escrow-status.js --network localhost" 2>&1)
    
    # Check for "isClaimed: true" or "isClaimed: false" in output
    if echo "$output" | grep -q "isClaimed: true"; then
        echo "true"
    elif echo "$output" | grep -q "isClaimed: false"; then
        echo "false"
    else
        echo "❌ PANIC: is_escrow_claimed failed to get escrow status" >&2
        echo "   escrow_addr: $escrow_addr, intent_id_evm: $intent_id_evm" >&2
        echo "   output: $output" >&2
        exit 1
    fi
}
