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
        # Script is in a subdirectory (e.g., testing-infra/e2e-tests-apt/)
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

# Fetch and display balances
# Usage: display_balances
# Fetches balances from aptos CLI and displays them on both terminal and log file
# Also shows EVM chain balances if EVM chain is running
display_balances() {
    # Fetch Aptos balances
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
    
    # Fetch EVM balances if EVM chain is running
    if curl -s -X POST http://127.0.0.1:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        >/dev/null 2>&1; then
        cd "$PROJECT_ROOT/evm-intent-framework"
        
        # Use the actual script files instead of inline heredoc (Hardhat doesn't support inline scripts)
        local alice_evm_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=0 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
        local alice_evm=$(echo "$alice_evm_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
        
        local solver_evm_output=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
        local solver_evm=$(echo "$solver_evm_output" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
        
        cd "$PROJECT_ROOT"
        
        # Always show Chain 3 (EVM) header when EVM chain is running
        log_and_echo "   Chain 3 (EVM):"
        
        # Format EVM balances (show both ETH and wei)
        if [ "$alice_evm" != "0" ] && [ -n "$alice_evm" ]; then
            local alice_eth=$(echo "scale=4; $alice_evm / 1000000000000000000" | bc 2>/dev/null || echo "N/A")
            log_and_echo "      Alice (Acc 0): ${alice_eth} ETH"
        else
            log_and_echo "      Alice (Acc 0): 0 ETH"
        fi
        
        if [ "$solver_evm" != "0" ] && [ -n "$solver_evm" ]; then
            local bob_eth=$(echo "scale=4; $solver_evm / 1000000000000000000" | bc 2>/dev/null || echo "N/A")
            log_and_echo "      Bob (Acc 1): ${bob_eth} ETH"
        else
            log_and_echo "      Bob (Acc 1): 0 ETH"
        fi
    fi
    
    log_and_echo ""
}

# Get address from aptos profile
# Usage: get_aptos_address <profile_name>
# Returns the account address for the given profile
get_aptos_address() {
    local profile="$1"
    aptos config show-profiles | jq -r ".[\"Result\"][\"$profile\"].account"
}

# Fund account and verify balance
# Usage: fund_and_verify_account <profile_name> <chain_number> <account_label> <expected_amount> [output_var_name]
# Example: fund_and_verify_account "alice-chain1" "1" "Alice Chain 1" "200000000" "ALICE_BALANCE"
# If output_var_name is provided, sets that variable with the verified balance
# Otherwise, outputs the balance (can be captured with: BALANCE=$(fund_and_verify_account ...))
fund_and_verify_account() {
    local profile="$1"
    local chain_num="$2"
    local account_label="$3"
    local expected_amount="${4:-100000000}"
    local output_var="$5"
    
    # Determine ports based on chain number
    local rest_port
    local faucet_port
    if [ "$chain_num" = "1" ]; then
        rest_port="8080"
        faucet_port="8081"
    elif [ "$chain_num" = "2" ]; then
        rest_port="8082"
        faucet_port="8083"
    else
        log_and_echo "❌ ERROR: Invalid chain number: $chain_num (must be 1 or 2)"
        exit 1
    fi
    
    log "Funding $account_label..."
    local address=$(get_aptos_address "$profile")
    local tx_hash=$(curl -s -X POST "http://127.0.0.1:${faucet_port}/mint?address=${address}&amount=100000000" | jq -r '.[0]')
    
    if [ "$tx_hash" != "null" ] && [ -n "$tx_hash" ]; then
        log "✅ $account_label funded successfully (tx: $tx_hash)"
        
        # Wait for funding to be processed
        log "⏳ Waiting for funding to be processed..."
        sleep 10
        
        # Get FA store address from transaction events
        local fa_store=$(curl -s "http://127.0.0.1:${rest_port}/v1/transactions/by_hash/${tx_hash}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
        
        if [ "$fa_store" != "null" ] && [ -n "$fa_store" ]; then
            local balance=$(curl -s "http://127.0.0.1:${rest_port}/v1/accounts/${fa_store}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
            
            if [ -z "$balance" ] || [ "$balance" = "null" ]; then
                log_and_echo "❌ ERROR: Failed to get $account_label balance"
                exit 1
            fi
            
            if [ "$balance" != "$expected_amount" ]; then
                log_and_echo "❌ ERROR: $account_label balance mismatch"
                log_and_echo "   Expected: $expected_amount Octas"
                log_and_echo "   Got: $balance Octas"
                exit 1
            fi
            
            log "✅ $account_label balance verified: $balance Octas"
            
            # Set output variable if provided, otherwise just return the balance
            if [ -n "$output_var" ]; then
                eval "$output_var=$balance"
            else
                echo "$balance"
            fi
        else
            log_and_echo "❌ ERROR: Could not verify $account_label balance via FA store"
            exit 1
        fi
    else
        log_and_echo "❌ Failed to fund $account_label"
        exit 1
    fi
}


