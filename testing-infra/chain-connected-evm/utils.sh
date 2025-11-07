#!/bin/bash

# EVM-specific utilities for testing infrastructure scripts
# This file MUST be sourced AFTER util.sh
# Usage: 
#   source "$(dirname "$0")/../util.sh"
#   source "$(dirname "$0")/utils.sh"
#
# Note: This file depends on functions from util.sh (log, log_and_echo, setup_project_root, etc.)

# Run Hardhat command with nix develop wrapper
# Usage: run_hardhat_command <command> [env_vars]
# Example: run_hardhat_command "npx hardhat run scripts/deploy.js --network localhost"
#          run_hardhat_command "npm install"
#          run_hardhat_command "npx hardhat run scripts/deploy.js --network localhost" "VERIFIER_ADDRESS='0x123'"
# Executes the command inside nix develop environment
# If env_vars are provided, they are prepended to the command
# Returns the exit code of the command
run_hardhat_command() {
    if [ -z "$1" ]; then
        log_and_echo "❌ ERROR: run_hardhat_command() requires a command"
        exit 1
    fi
    
    local cmd="$1"
    local env_vars="${2:-}"
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    cd "$PROJECT_ROOT/evm-intent-framework"
    
    if [ -n "$env_vars" ]; then
        nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && $env_vars $cmd"
    else
        nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && $cmd"
    fi
    
    local exit_code=$?
    cd "$PROJECT_ROOT"
    return $exit_code
}

# Check if EVM chain is running
# Usage: check_evm_chain_running [port]
# Example: check_evm_chain_running
#          check_evm_chain_running "8545"
# Checks if EVM chain is responding on the specified port (default: 8545)
# Returns 0 if chain is running, 1 if not
check_evm_chain_running() {
    local port="${1:-8545}"
    
    if curl -s -X POST "http://127.0.0.1:${port}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get Hardhat account address by index
# Usage: get_hardhat_account_address <account_index> [network]
# Example: get_hardhat_account_address "0"
#          get_hardhat_account_address "1" "localhost"
# Returns the Ethereum address for the specified account index (0, 1, 2, etc.)
# Uses get-account-address.js script with ACCOUNT_INDEX environment variable
get_hardhat_account_address() {
    local account_index="$1"
    local network="${2:-localhost}"
    
    if [ -z "$account_index" ]; then
        log_and_echo "❌ ERROR: get_hardhat_account_address() requires an account index"
        exit 1
    fi
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    local address=$(run_hardhat_command "npx hardhat run scripts/get-account-address.js --network $network" "ACCOUNT_INDEX=$account_index" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n')
    
    if [ -z "$address" ]; then
        log_and_echo "❌ ERROR: Could not get Hardhat account address for index $account_index"
        exit 1
    fi
    
    echo "$address"
}

# Extract vault address from deployment output or log files
# Usage: extract_vault_address [deploy_output] [log_file_pattern]
# Example: extract_vault_address "$DEPLOY_OUTPUT"
#          extract_vault_address "" "deploy-contract*.log"
# Extracts the IntentVault contract address from:
#   1. Deployment output (if provided)
#   2. Log files matching pattern (if provided)
#   3. Falls back to searching log files in tmp/intent-framework-logs/
# Returns the vault address or exits with error if not found
extract_vault_address() {
    local deploy_output="$1"
    local log_file_pattern="${2:-deploy-contract*.log}"
    
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi
    
    local vault_address=""
    
    # First, try to extract from deployment output if provided
    if [ -n "$deploy_output" ]; then
        vault_address=$(echo "$deploy_output" | grep -i "IntentVault deployed to" | awk '{print $NF}' | tr -d '\n')
        
        if [ -z "$vault_address" ]; then
            # Try alternative pattern (any 0x followed by 40 hex chars)
            vault_address=$(echo "$deploy_output" | grep -oE "0x[a-fA-F0-9]{40}" | head -1)
        fi
    fi
    
    # If not found in output, try log files
    if [ -z "$vault_address" ]; then
        local log_dir="$PROJECT_ROOT/tmp/intent-framework-logs"
        if [ -d "$log_dir" ]; then
            vault_address=$(grep -i "IntentVault deployed to" "$log_dir"/$log_file_pattern 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
        fi
    fi
    
    if [ -z "$vault_address" ]; then
        log_and_echo "❌ ERROR: Could not extract vault address"
        if [ -n "$deploy_output" ]; then
            log_and_echo "   Deployment output:"
            echo "$deploy_output" | head -20
        fi
        exit 1
    fi
    
    echo "$vault_address"
}

# Convert intent ID from Aptos format to EVM format
# Usage: convert_intent_id_to_evm <intent_id>
# Returns: EVM-formatted intent ID (0x-prefixed, 64 hex chars) via stdout
# Input: intent_id in hex format (0x...)
# Output: intent_id padded to 64 characters (32 bytes) with 0x prefix
convert_intent_id_to_evm() {
    local intent_id="$1"
    
    if [ -z "$intent_id" ]; then
        log_and_echo "❌ ERROR: convert_intent_id_to_evm() requires an intent_id"
        exit 1
    fi
    
    # Remove 0x prefix if present
    local intent_id_hex
    intent_id_hex=$(echo "$intent_id" | sed 's/^0x//')
    
    # Pad to 64 characters (32 bytes) with leading zeros
    intent_id_hex=$(printf "%064s" "$intent_id_hex" | tr ' ' '0')
    
    # Add 0x prefix and output
    echo "0x$intent_id_hex"
}

