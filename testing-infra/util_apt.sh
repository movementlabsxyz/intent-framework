#!/bin/bash

# Aptos-specific utilities for testing infrastructure scripts
# This file MUST be sourced AFTER util.sh
# Usage: 
#   source "$(dirname "$0")/../util.sh"
#   source "$(dirname "$0")/../util_apt.sh"
#
# Note: This file depends on functions from util.sh (log, log_and_echo, setup_project_root, etc.)

# Get address from aptos profile
# Usage: get_profile_address <profile_name>
# Returns the account address for the given profile
# Standardizes the pattern: aptos config show-profiles | jq -r '.["Result"]["<profile>"].account'
get_profile_address() {
    local profile="$1"
    
    if [ -z "$profile" ]; then
        log_and_echo "❌ ERROR: get_profile_address() requires a profile name"
        exit 1
    fi
    
    local address=$(aptos config show-profiles | jq -r ".[\"Result\"][\"$profile\"].account" 2>/dev/null)
    
    if [ -z "$address" ] || [ "$address" = "null" ]; then
        log_and_echo "❌ ERROR: Could not extract address for profile: $profile"
        exit 1
    fi
    
    echo "$address"
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
    local address=$(get_profile_address "$profile")
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

# Initialize Aptos profile
# Usage: init_aptos_profile <profile_name> <chain_number> [log_file]
# Example: init_aptos_profile "alice-chain1" "1"
#          init_aptos_profile "alice-chain2" "2"
# Creates an Aptos profile for the specified chain:
#   - Chain 1 (hub): uses --network local (ports 8080/8081)
#   - Chain 2 (connected): uses --network custom with --rest-url and --faucet-url (ports 8082/8083)
# If log_file is provided, redirects output there; otherwise uses LOG_FILE if set
init_aptos_profile() {
    local profile="$1"
    local chain_num="$2"
    local log_file="${3:-$LOG_FILE}"
    
    if [ -z "$profile" ]; then
        log_and_echo "❌ ERROR: init_aptos_profile() requires a profile name"
        exit 1
    fi
    
    if [ -z "$chain_num" ]; then
        log_and_echo "❌ ERROR: init_aptos_profile() requires a chain number (1 or 2)"
        exit 1
    fi
    
    if [ "$chain_num" != "1" ] && [ "$chain_num" != "2" ]; then
        log_and_echo "❌ ERROR: Invalid chain number: $chain_num (must be 1 or 2)"
        exit 1
    fi
    
    local aptos_cmd
    if [ "$chain_num" = "1" ]; then
        # Chain 1 (hub): use local network
        aptos_cmd="printf \"\\n\" | aptos init --profile $profile --network local --assume-yes"
    else
        # Chain 2 (connected): use custom network with specific ports
        aptos_cmd="printf \"\\n\" | aptos init --profile $profile --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes"
    fi
    
    if [ -n "$log_file" ]; then
        if eval "$aptos_cmd >> \"$log_file\" 2>&1"; then
            log "✅ Profile $profile created successfully on Chain $chain_num"
            return 0
        else
            log_and_echo "❌ Failed to create profile $profile on Chain $chain_num"
            exit 1
        fi
    else
        if eval "$aptos_cmd"; then
            log "✅ Profile $profile created successfully on Chain $chain_num"
            return 0
        else
            log_and_echo "❌ Failed to create profile $profile on Chain $chain_num"
            exit 1
        fi
    fi
}

# Cleanup Aptos profile
# Usage: cleanup_aptos_profile <profile_name> [log_file]
# Example: cleanup_aptos_profile "alice-chain1"
#          cleanup_aptos_profile "intent-account-chain2"
# Deletes an Aptos profile using aptos config delete-profile
# If log_file is provided, redirects output there; otherwise uses LOG_FILE if set
# Always succeeds (|| true) to allow cleanup in scripts that may run multiple times
cleanup_aptos_profile() {
    local profile="$1"
    local log_file="${2:-$LOG_FILE}"
    
    if [ -z "$profile" ]; then
        log_and_echo "❌ ERROR: cleanup_aptos_profile() requires a profile name"
        exit 1
    fi
    
    if [ -n "$log_file" ]; then
        aptos config delete-profile --profile "$profile" >> "$log_file" 2>&1 || true
    else
        aptos config delete-profile --profile "$profile" 2>&1 || true
    fi
}

# Wait for Aptos chain to be ready
# Usage: wait_for_aptos_chain_ready <chain_number> [max_attempts] [sleep_seconds]
# Example: wait_for_aptos_chain_ready "1"
#          wait_for_aptos_chain_ready "2" "30" "5"
# Waits for both REST API and faucet to be ready:
#   - Chain 1: checks ports 8080 (REST) and 8081 (faucet)
#   - Chain 2: checks ports 8082 (REST) and 8083 (faucet)
# Default: 30 attempts with 5 second intervals
# Returns 0 if chain is ready, exits with error if timeout
wait_for_aptos_chain_ready() {
    local chain_num="$1"
    local max_attempts="${2:-30}"
    local sleep_seconds="${3:-5}"
    
    if [ -z "$chain_num" ]; then
        log_and_echo "❌ ERROR: wait_for_aptos_chain_ready() requires a chain number (1 or 2)"
        exit 1
    fi
    
    if [ "$chain_num" != "1" ] && [ "$chain_num" != "2" ]; then
        log_and_echo "❌ ERROR: Invalid chain number: $chain_num (must be 1 or 2)"
        exit 1
    fi
    
    local rest_port
    local faucet_port
    if [ "$chain_num" = "1" ]; then
        rest_port="8080"
        faucet_port="8081"
    else
        rest_port="8082"
        faucet_port="8083"
    fi
    
    log "   - Waiting for Chain $chain_num services..."
    for i in $(seq 1 "$max_attempts"); do
        if curl -s "http://127.0.0.1:${rest_port}/v1/ledger/info" >/dev/null 2>&1 && \
           curl -s "http://127.0.0.1:${faucet_port}/" >/dev/null 2>&1; then
            log "   ✅ Chain $chain_num ready!"
            return 0
        fi
        log "   Waiting... (attempt $i/$max_attempts)"
        sleep "$sleep_seconds"
    done
    
    log_and_echo "❌ ERROR: Chain $chain_num failed to start after $max_attempts attempts"
    log_and_echo "   REST API (port $rest_port) or faucet (port $faucet_port) not responding"
    exit 1
}

# Verify Aptos chain services are running
# Usage: verify_aptos_chain_services <chain_number>
# Example: verify_aptos_chain_services "1"
#          verify_aptos_chain_services "2"
# Verifies both REST API and faucet are responding correctly:
#   - REST API: checks http://127.0.0.1:<rest_port>/v1
#   - Faucet: checks http://127.0.0.1:<faucet_port>/ should return "tap:ok"
#   - Chain 1: ports 8080 (REST) and 8081 (faucet)
#   - Chain 2: ports 8082 (REST) and 8083 (faucet)
# Exits with error if any service is not responding correctly
verify_aptos_chain_services() {
    local chain_num="$1"
    
    if [ -z "$chain_num" ]; then
        log_and_echo "❌ ERROR: verify_aptos_chain_services() requires a chain number (1 or 2)"
        exit 1
    fi
    
    if [ "$chain_num" != "1" ] && [ "$chain_num" != "2" ]; then
        log_and_echo "❌ ERROR: Invalid chain number: $chain_num (must be 1 or 2)"
        exit 1
    fi
    
    local rest_port
    local faucet_port
    if [ "$chain_num" = "1" ]; then
        rest_port="8080"
        faucet_port="8081"
    else
        rest_port="8082"
        faucet_port="8083"
    fi
    
    # Verify REST API
    log "   - Verifying Chain $chain_num REST API..."
    if ! curl -s "http://127.0.0.1:${rest_port}/v1" > /dev/null; then
        log_and_echo "❌ Error: Chain $chain_num failed to start on port $rest_port"
        exit 1
    fi
    log "   ✅ Chain $chain_num REST API is running"
    
    # Verify faucet
    log "   - Verifying faucet..."
    local faucet_response=$(curl -s "http://127.0.0.1:${faucet_port}/" 2>/dev/null || echo "")
    
    if [ "$faucet_response" = "tap:ok" ]; then
        log "   ✅ Chain $chain_num faucet is running"
    else
        log_and_echo "❌ Error: Chain $chain_num faucet failed to start on port $faucet_port"
        exit 1
    fi
}

# Extract APT metadata address from Aptos chain
# Usage: extract_apt_metadata <profile> <chain_address> <account_address> <chain_num> [log_file]
# Returns: metadata address via stdout, exits on error
# chain_num: 1 for Chain 1 (hub, port 8080), 2 for Chain 2 (connected, port 8082)
extract_apt_metadata() {
    local profile="$1"
    local chain_address="$2"
    local account_address="$3"
    local chain_num="$4"
    local log_file="${5:-$LOG_FILE}"
    
    if [ -z "$profile" ]; then
        log_and_echo "❌ ERROR: extract_apt_metadata() requires a profile name"
        exit 1
    fi
    
    if [ -z "$chain_address" ]; then
        log_and_echo "❌ ERROR: extract_apt_metadata() requires a chain address"
        exit 1
    fi
    
    if [ -z "$account_address" ]; then
        log_and_echo "❌ ERROR: extract_apt_metadata() requires an account address"
        exit 1
    fi
    
    if [ -z "$chain_num" ]; then
        log_and_echo "❌ ERROR: extract_apt_metadata() requires a chain number (1 or 2)"
        exit 1
    fi
    
    if [ "$chain_num" != "1" ] && [ "$chain_num" != "2" ]; then
        log_and_echo "❌ ERROR: Invalid chain number: $chain_num (must be 1 or 2)"
        exit 1
    fi
    
    # Determine REST API port based on chain number
    local rest_port
    if [ "$chain_num" = "1" ]; then
        rest_port="8080"
    else
        rest_port="8082"
    fi
    
    # Run aptos move command to get APT metadata
    local aptos_cmd="aptos move run --profile $profile --assume-yes --function-id \"0x${chain_address}::test_fa_helper::get_apt_metadata_address\""
    
    if [ -n "$log_file" ]; then
        if ! eval "$aptos_cmd >> \"$log_file\" 2>&1"; then
            log_and_echo "❌ Failed to get APT metadata on Chain $chain_num"
            exit 1
        fi
    else
        if ! eval "$aptos_cmd"; then
            log_and_echo "❌ Failed to get APT metadata on Chain $chain_num"
            exit 1
        fi
    fi
    
    # Wait for transaction to be processed
    sleep 2
    
    # Query REST API for the account's latest transaction and extract metadata
    local metadata
    metadata=$(curl -s "http://127.0.0.1:${rest_port}/v1/accounts/${account_address}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("APTMetadataAddressEvent")) | .data.metadata' | head -n 1)
    
    if [ -z "$metadata" ] || [ "$metadata" = "null" ]; then
        log_and_echo "❌ Failed to extract APT metadata from Chain $chain_num transaction"
        exit 1
    fi
    
    # Output metadata address
    echo "$metadata"
}

