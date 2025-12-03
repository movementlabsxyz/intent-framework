#!/bin/bash

# Aptos-specific utilities for testing infrastructure scripts
# This file MUST be sourced AFTER util.sh
# Usage: 
#   source "$(dirname "$0")/../util.sh"
#   source "$(dirname "$0")/../util_mvm.sh"
#
# Note: This file depends on functions from util.sh (log, log_and_echo, setup_project_root, etc.)

# Get address from aptos profile
# Usage: get_profile_address <profile_name>
# Returns the account address for the given profile
# Standardizes the pattern: aptos config show-profiles | jq -r '.["Result"]["<profile>"].account'
get_profile_address() {
    local profile="$1"
    
    if [ -z "$profile" ]; then
        echo "❌ ERROR: get_profile_address() requires a profile name" >&2
        return 1
    fi
    
    local address=$(aptos config show-profiles | jq -r ".[\"Result\"][\"$profile\"].account" 2>/dev/null)
    
    if [ -z "$address" ] || [ "$address" = "null" ]; then
        echo "❌ ERROR: Could not extract address for profile: $profile" >&2
        return 1
    fi
    
    echo "$address"
}

# Fund account and verify balance
# Usage: fund_and_verify_account <profile_name> <chain_number> <account_label> <expected_amount> [output_var_name]
# Example: fund_and_verify_account "requester-chain1" "1" "Requester Chain 1" "200000000" "REQUESTER_BALANCE"
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
# Example: init_aptos_profile "requester-chain1" "1"
#          init_aptos_profile "requester-chain2" "2"
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
# Example: cleanup_aptos_profile "requester-chain1"
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
    local aptos_cmd="aptos move run --profile $profile --assume-yes --function-id \"0x${chain_address}::utils::get_apt_metadata_address\""
    
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

# Generate solver signature for IntentToSign
# Usage: generate_solver_signature <profile> <chain_address> <offered_metadata> <offered_amount> <offered_chain_id> <desired_metadata> <desired_amount> <desired_chain_id> <expiry_time> <issuer> <solver> <chain_num> [log_file]
# Example: generate_solver_signature "solver-chain1" "$CHAIN1_ADDRESS" "$OFFERED_METADATA" "100000000" "1" "$DESIRED_METADATA" "100000000" "2" "$EXPIRY_TIME" "$REQUESTER_CHAIN1_ADDRESS" "$SOLVER_CHAIN1_ADDRESS" "1"
# Returns the signature as hex string (with 0x prefix)
generate_solver_signature() {
    local profile="$1"
    local chain_address="$2"
    local offered_metadata="$3"
    local offered_amount="$4"
    local offered_chain_id="$5"
    local desired_metadata="$6"
    local desired_amount="$7"
    local desired_chain_id="$8"
    local expiry_time="$9"
    local issuer="${10}"
    local solver="${11}"
    local chain_num="${12}"
    local log_file="${13:-$LOG_FILE}"

    if [ -z "$profile" ] || [ -z "$chain_address" ] || [ -z "$offered_metadata" ] || [ -z "$offered_amount" ] || [ -z "$offered_chain_id" ] || [ -z "$desired_metadata" ] || [ -z "$desired_amount" ] || [ -z "$desired_chain_id" ] || [ -z "$expiry_time" ] || [ -z "$issuer" ] || [ -z "$solver" ] || [ -z "$chain_num" ]; then
        log_and_echo "❌ ERROR: generate_solver_signature() requires all parameters"
        exit 1
    fi

    # Ensure PROJECT_ROOT is set
    if [ -z "$PROJECT_ROOT" ]; then
        setup_project_root
    fi

    # Normalize addresses to ensure they have 0x prefix (required by get_intent_hash)
    # aptos config returns addresses without 0x prefix, but get_intent_hash requires it
    normalize_address() {
        local addr="$1"
        if [ "${addr#0x}" != "$addr" ]; then
            # Already has 0x prefix
            echo "$addr"
        else
            # Add 0x prefix
            echo "0x$addr"
        fi
    }
    
    # Strip 0x from chain_address (used in function ID format: 0x{chain_address}::...)
    strip_0x() {
        local addr="$1"
        if [ "${addr#0x}" != "$addr" ]; then
            # Has 0x prefix, strip it
            echo "${addr#0x}"
        else
            # No prefix, return as-is
            echo "$addr"
        fi
    }
    
    local normalized_issuer=$(normalize_address "$issuer")
    local normalized_solver=$(normalize_address "$solver")
    local normalized_chain_address=$(strip_0x "$chain_address")  # Strip 0x for function ID format
    local normalized_offered_metadata=$(normalize_address "$offered_metadata")
    local normalized_desired_metadata=$(normalize_address "$desired_metadata")
    
    # Run the Rust binary to generate signature
    # Use a temp file to capture output while also logging
    local temp_output_file
    temp_output_file=$(mktemp)
    
    local exit_code
    if [ -n "$log_file" ]; then
        # Run command, log everything, and capture to temp file
        # Pass HOME environment variable to ensure Aptos config can be found
        (cd "$PROJECT_ROOT" && env HOME="${HOME}" nix develop -c bash -c "cd solver && cargo run --bin sign_intent -- --profile \"$profile\" --chain-address \"$normalized_chain_address\" --offered-metadata \"$normalized_offered_metadata\" --offered-amount \"$offered_amount\" --offered-chain-id \"$offered_chain_id\" --desired-metadata \"$normalized_desired_metadata\" --desired-amount \"$desired_amount\" --desired-chain-id \"$desired_chain_id\" --expiry-time \"$expiry_time\" --issuer \"$normalized_issuer\" --solver \"$normalized_solver\" --chain-num \"$chain_num\" 2>&1" | tee -a "$log_file" > "$temp_output_file")
        exit_code=${PIPESTATUS[0]}
    else
        # Run command and capture to temp file
        # Pass HOME environment variable to ensure Aptos config can be found
        (cd "$PROJECT_ROOT" && env HOME="${HOME}" nix develop -c bash -c "cd solver && cargo run --bin sign_intent -- --profile \"$profile\" --chain-address \"$normalized_chain_address\" --offered-metadata \"$normalized_offered_metadata\" --offered-amount \"$offered_amount\" --offered-chain-id \"$offered_chain_id\" --desired-metadata \"$normalized_desired_metadata\" --desired-amount \"$desired_amount\" --desired-chain-id \"$desired_chain_id\" --expiry-time \"$expiry_time\" --issuer \"$normalized_issuer\" --solver \"$normalized_solver\" --chain-num \"$chain_num\" 2>&1" > "$temp_output_file")
        exit_code=$?
    fi
    
    # Read output from temp file
    local temp_output
    temp_output=$(cat "$temp_output_file")
    rm -f "$temp_output_file"
    
    # Check if command succeeded
    if [ $exit_code -ne 0 ]; then
        log_and_echo "❌ ERROR: Failed to generate solver signature (exit code: $exit_code)"
        # Print error output to stderr so it's visible in CI
        echo "Error output:" >&2
        echo "$temp_output" >&2
        if [ -n "$log_file" ]; then
            log "   Error output: $temp_output"
        fi
        exit 1
    fi
    
    # Extract signature from output (line that matches hex pattern: 0x + 128 hex chars = 130 total)
    local signature
    signature=$(echo "$temp_output" | grep -E '^0x[0-9a-fA-F]{128}$' | tail -1)
    
    if [ -z "$signature" ] || [[ ! "$signature" =~ ^0x[0-9a-fA-F]{128}$ ]]; then
        log_and_echo "❌ ERROR: Failed to extract valid signature from output"
        # Print output to stderr so it's visible in CI
        echo "Command output:" >&2
        echo "$temp_output" >&2
        if [ -n "$log_file" ]; then
            log "   Output was: $temp_output"
        fi
        exit 1
    fi

    echo "$signature"
}

# Initialize solver registry (must be called once before registering solvers)
# Usage: initialize_solver_registry <profile> <chain_address> [log_file]
# Example: initialize_solver_registry "intent-account-chain1" "$CHAIN1_ADDRESS"
# Exits on error (except if already initialized, which is handled gracefully)
initialize_solver_registry() {
    local profile="$1"
    local chain_address="$2"
    local log_file="${3:-$LOG_FILE}"

    if [ -z "$profile" ] || [ -z "$chain_address" ]; then
        log_and_echo "❌ ERROR: initialize_solver_registry() requires profile and chain_address"
        exit 1
    fi

    log "     Initializing solver registry..."
    local init_output
    local init_status
    if [ -n "$log_file" ]; then
        init_output=$(aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::initialize" 2>&1 | tee -a "$log_file")
        init_status=${PIPESTATUS[0]}
    else
        init_output=$(aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::initialize" 2>&1)
        init_status=$?
    fi

    if [ $init_status -eq 0 ]; then
        log "     ✅ Solver registry initialized successfully"
    elif echo "$init_output" | grep -q "E_ALREADY_INITIALIZED\|E2\|already initialized"; then
        log "     ℹ️  Solver registry already initialized (skipping)"
    else
        log_and_echo "     ❌ Failed to initialize solver registry"
        exit 1
    fi
}

# Get USDxyz metadata address
# Usage: get_usdxyz_metadata <test_tokens_address> <chain_num>
# Returns the USDxyz metadata object address
get_usdxyz_metadata() {
    local test_tokens_addr="$1"
    local chain_num="$2"
    
    local rest_port
    if [ "$chain_num" = "1" ]; then
        rest_port="8080"
    else
        rest_port="8082"
    fi
    
    # Call the view function to get metadata
    local metadata=$(curl -s "http://127.0.0.1:${rest_port}/v1/view" \
        -H 'Content-Type: application/json' \
        -d "{
            \"function\": \"${test_tokens_addr}::usdxyz::get_metadata\",
            \"type_arguments\": [],
            \"arguments\": []
        }" 2>/dev/null | jq -r '.[0].inner // empty')
    
    echo "$metadata"
}

# Get USDxyz balance for an account
# Usage: get_usdxyz_balance <profile> <chain_num> <test_tokens_address>
# Returns the USDxyz balance for the given profile
get_usdxyz_balance() {
    local profile="$1"
    local chain_num="$2"
    local test_tokens_addr="$3"
    
    # Validate inputs
    if [ -z "$profile" ] || [ -z "$chain_num" ] || [ -z "$test_tokens_addr" ]; then
        echo "❌ PANIC: get_usdxyz_balance requires profile, chain_num, test_tokens_addr" >&2
        echo "   profile: '$profile', chain_num: '$chain_num', test_tokens_addr: '$test_tokens_addr'" >&2
        exit 1
    fi
    
    local rest_port
    if [ "$chain_num" = "1" ]; then
        rest_port="8080"
    else
        rest_port="8082"
    fi
    
    # Use || true to allow PANIC check to run if get_profile_address fails
    local account_addr=$(get_profile_address "$profile" 2>/dev/null) || true
    if [ -z "$account_addr" ]; then
        echo "❌ PANIC: get_usdxyz_balance failed to get address for profile '$profile'" >&2
        exit 1
    fi
    
    # Call the view function to get balance
    local balance=$(curl -s "http://127.0.0.1:${rest_port}/v1/view" \
        -H 'Content-Type: application/json' \
        -d "{
            \"function\": \"${test_tokens_addr}::usdxyz::balance\",
            \"type_arguments\": [],
            \"arguments\": [\"${account_addr}\"]
        }" 2>/dev/null | jq -r '.[0] // ""')
    
    if [ -z "$balance" ]; then
        echo "❌ PANIC: get_usdxyz_balance failed to get balance for '$profile' on chain $chain_num" >&2
        echo "   account_addr: $account_addr, test_tokens_addr: $test_tokens_addr" >&2
        exit 1
    fi
    
    echo "$balance"
}

# Display balances for Chain 1 (Hub)
# Usage: display_balances_hub [test_tokens_address]
# Fetches and displays Requester and Solver balances on the Hub chain
# If test_tokens_address is provided, also displays USDxyz balances (PANICS if USDxyz lookup fails)
# Note: Hub chain is always a Move VM chain, so this uses aptos commands
display_balances_hub() {
    local test_tokens_addr="$1"
    
    local requester1=$(aptos account balance --profile requester-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    local solver1=$(aptos account balance --profile solver-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    
    log_and_echo ""
    log_and_echo "   Chain 1 (Hub):"
    
    if [ -n "$test_tokens_addr" ]; then
        local requester_usdxyz=$(get_usdxyz_balance "requester-chain1" "1" "$test_tokens_addr")
        local solver_usdxyz=$(get_usdxyz_balance "solver-chain1" "1" "$test_tokens_addr")
        
        # PANIC if we passed a token address but couldn't get balances
        if [ -z "$requester_usdxyz" ] || [ -z "$solver_usdxyz" ]; then
            log_and_echo "❌ PANIC: display_balances_hub failed to get USDxyz balances"
            log_and_echo "   test_tokens_addr: $test_tokens_addr"
            log_and_echo "   requester_usdxyz: '$requester_usdxyz'"
            log_and_echo "   solver_usdxyz: '$solver_usdxyz'"
            exit 1
        fi
        
        log_and_echo "      Requester: $requester1 Octas APT, $requester_usdxyz USDxyz"
        log_and_echo "      Solver:   $solver1 Octas APT, $solver_usdxyz USDxyz"
    else
        log_and_echo "      Requester: $requester1 Octas"
        log_and_echo "      Solver:   $solver1 Octas"
    fi
}

# Display balances for Chain 2 (Connected Move VM)
# Usage: display_balances_connected_mvm [test_tokens_address]
# Fetches and displays Requester and Solver balances on the Connected Move VM chain
# If test_tokens_address is provided, also displays USDxyz balances (PANICS if USDxyz lookup fails)
# Only displays if Chain 2 profiles exist (skips silently if they don't)
display_balances_connected_mvm() {
    local test_tokens_addr="$1"
    
    # Check if Chain 2 profiles exist
    if ! aptos config show-profiles 2>/dev/null | jq -r ".[\"Result\"][\"requester-chain2\"]" 2>/dev/null | grep -q "."; then
        return 0  # Silently skip if profiles don't exist
    fi
    
    local requester2=$(aptos account balance --profile requester-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    local solver2=$(aptos account balance --profile solver-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    
    log_and_echo "   Chain 2 (Connected MVM):"
    
    if [ -n "$test_tokens_addr" ]; then
        local requester_usdxyz=$(get_usdxyz_balance "requester-chain2" "2" "$test_tokens_addr")
        local solver_usdxyz=$(get_usdxyz_balance "solver-chain2" "2" "$test_tokens_addr")
        
        # PANIC if we passed a token address but couldn't get balances
        if [ -z "$requester_usdxyz" ] || [ -z "$solver_usdxyz" ]; then
            log_and_echo "❌ PANIC: display_balances_connected_mvm failed to get USDxyz balances"
            log_and_echo "   test_tokens_addr: $test_tokens_addr"
            log_and_echo "   requester_usdxyz: '$requester_usdxyz'"
            log_and_echo "   solver_usdxyz: '$solver_usdxyz'"
            exit 1
        fi
        
        log_and_echo "      Requester: $requester2 Octas APT, $requester_usdxyz USDxyz"
        log_and_echo "      Solver:   $solver2 Octas APT, $solver_usdxyz USDxyz"
    else
        log_and_echo "      Requester: $requester2 Octas"
        log_and_echo "      Solver:   $solver2 Octas"
    fi
}

# Register solver in the solver registry
# Usage: register_solver <profile> <chain_address> <public_key_hex> <evm_address_hex> [connected_chain_mvm_address] [log_file]
# Example: register_solver "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY_HEX" "0x0000000000000000000000000000000000000001"
# Example with MVM address: register_solver "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY_HEX" "0x0000000000000000000000000000000000000001" "$SOLVER_CHAIN2_ADDRESS"
# Exits on error
register_solver() {
    local profile="$1"
    local chain_address="$2"
    local public_key_hex="$3"
    local evm_address_hex="$4"
    local connected_chain_mvm_address="${5:-}"  # Optional: Move VM address on connected chain
    local log_file="${6:-$LOG_FILE}"

    if [ -z "$profile" ] || [ -z "$chain_address" ] || [ -z "$public_key_hex" ] || [ -z "$evm_address_hex" ]; then
        log_and_echo "❌ ERROR: register_solver() requires profile, chain_address, public_key_hex, and evm_address_hex"
        exit 1
    fi

    # Remove 0x prefix if present
    public_key_hex="${public_key_hex#0x}"
    evm_address_hex="${evm_address_hex#0x}"
    if [ -n "$connected_chain_mvm_address" ]; then
        connected_chain_mvm_address="${connected_chain_mvm_address#0x}"
    fi

    log "     Registering solver in registry..."
    
    # Debug: Log input parameters
    log "     DEBUG: Input parameters:"
    log "       profile: $profile"
    log "       chain_address: $chain_address"
    log "       public_key_hex (length): ${#public_key_hex} chars"
    log "       evm_address_hex: $evm_address_hex (length: ${#evm_address_hex} chars)"
    log "       connected_chain_mvm_address: ${connected_chain_mvm_address:-<empty>}"
    
    # Build arguments: public_key, evm_address, mvm_address
    # Use sentinel values: empty vector (hex:) for EVM address if not provided, 0x0 for MVM address if not provided
    local evm_arg
    if [ -n "$evm_address_hex" ]; then
        evm_arg="hex:${evm_address_hex}"
    else
        # Use sentinel: empty vector (no hex value)
        evm_arg="hex:"
    fi
    
    local mvm_arg
    if [ -n "$connected_chain_mvm_address" ]; then
        mvm_arg="address:0x${connected_chain_mvm_address}"
    else
        # Use sentinel: zero address
        mvm_arg="address:0x0"
    fi
    
    # Debug: Log built arguments
    log "     DEBUG: Built arguments:"
    log "       public_key: hex:${public_key_hex:0:20}... (${#public_key_hex} chars)"
    log "       evm_address: $evm_arg"
    log "       mvm_address: $mvm_arg"
    log "     DEBUG: Full command:"
    log "       aptos move run --profile $profile --assume-yes \\"
    log "         --function-id 0x${chain_address}::solver_registry::register_solver \\"
    log "         --args \"hex:${public_key_hex}\" \"$evm_arg\" \"$mvm_arg\""
    
    if [ -n "$log_file" ]; then
        aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::register_solver" \
            --args "hex:${public_key_hex}" "$evm_arg" "$mvm_arg" >> "$log_file" 2>&1
    else
        aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::register_solver" \
            --args "hex:${public_key_hex}" "$evm_arg" "$mvm_arg"
    fi

    if [ $? -eq 0 ]; then
        log "     ✅ Solver registered successfully"
    else
        log_and_echo "     ❌ Failed to register solver"
        if [ -n "$log_file" ]; then
            log_and_echo "     Full error details in: $log_file"
            log_and_echo "     + + + + + + + + + + + + + + + + + + + +"
            cat "$log_file"
            log_and_echo "     + + + + + + + + + + + + + + + + + + + +"
        fi
        exit 1
    fi
}

# Verify that a solver is registered in the solver registry
# Usage: verify_solver_registered <profile> <chain_address> <solver_address> [log_file]
# Exits on error if solver is not registered
verify_solver_registered() {
    local profile="$1"
    local chain_address="$2"
    local solver_address="$3"
    local log_file="${4:-$LOG_FILE}"

    if [ -z "$profile" ] || [ -z "$chain_address" ] || [ -z "$solver_address" ]; then
        log_and_echo "❌ ERROR: verify_solver_registered() requires profile, chain_address, and solver_address"
        exit 1
    fi

    # Remove 0x prefix if present
    solver_address="${solver_address#0x}"
    chain_address="${chain_address#0x}"

    log "     Verifying solver is registered in registry..."
    
    # Call the entry function to check registration status
    # The function emits an event - we'll check the event to see if solver is registered
    local temp_file=$(mktemp)
    local rpc_url=$(aptos config show-profiles | jq -r ".[\"Result\"][\"$profile\"].rest_url" 2>/dev/null || echo "http://127.0.0.1:8080")
    local solver_addr_hex="0x${solver_address}"
    
    if [ -n "$log_file" ]; then
        aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::check_solver_registered" \
            --args "address:0x${solver_address}" \
            > "$temp_file" 2>&1
        local exit_code=$?
        cat "$temp_file" | tee -a "$log_file" > /dev/null
    else
        aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::check_solver_registered" \
            --args "address:0x${solver_address}" \
            > "$temp_file" 2>&1
        local exit_code=$?
    fi
    
    # Check if the command succeeded
    if [ $exit_code -ne 0 ]; then
        log_and_echo "❌ ERROR: Failed to query solver registry"
        log_and_echo "   Solver address: 0x${solver_address}"
        log_and_echo "   Registry address: 0x${chain_address}"
        log_and_echo "   Command result:"
        cat "$temp_file" | while IFS= read -r line; do
            log_and_echo "     $line"
        done
        rm -f "$temp_file"
        exit 1
    fi
    
    # Wait a moment for transaction to be processed
    sleep 2
    
    # Query the event from the transaction to check if solver is registered
    # Get the latest transaction from the account that called the function
    local tx_result=$(curl -s "${rpc_url}/v1/accounts/${solver_addr_hex}/transactions?limit=1" 2>/dev/null)
    local public_key_length=$(echo "$tx_result" | jq -r '.[0].events[]? | select(.type | contains("SolverRegistered")) | .data.public_key | length' 2>/dev/null)
    
    rm -f "$temp_file"
    
    # If public_key has length > 0, solver is registered
    if [ -n "$public_key_length" ] && [ "$public_key_length" != "null" ] && [ "$public_key_length" -gt 0 ]; then
        log "     ✅ Solver is registered in registry"
    else
        log_and_echo "❌ ERROR: Solver is not registered in registry"
        log_and_echo "   Solver address: 0x${solver_address}"
        log_and_echo "   Registry address: 0x${chain_address}"
        log_and_echo ""
        log_and_echo "   Available registered solvers:"
        list_all_solvers "$profile" "$chain_address" "$log_file"
        exit 1
    fi
}

# List all registered solvers from the solver registry
# Usage: list_all_solvers <profile> <chain_address> [log_file]
# Outputs all registered solvers with their details
list_all_solvers() {
    local profile="$1"
    local chain_address="$2"
    local log_file="${3:-$LOG_FILE}"

    if [ -z "$profile" ] || [ -z "$chain_address" ]; then
        log_and_echo "❌ ERROR: list_all_solvers() requires profile and chain_address"
        exit 1
    fi

    log "     Querying all registered solvers from registry..."

    # Remove 0x prefix if present
    chain_address="${chain_address#0x}"

    # Get RPC URL for the profile
    local rpc_url=$(aptos config show-profiles | jq -r ".[\"Result\"][\"$profile\"].rest_url" 2>/dev/null || echo "http://127.0.0.1:8080")
    
    # Call the Move entry function to list all solvers
    local temp_file=$(mktemp)
    local caller_address=$(aptos config show-profiles | jq -r ".[\"Result\"][\"$profile\"].account" 2>/dev/null)
    
    if [ -z "$caller_address" ] || [ "$caller_address" = "null" ]; then
        log_and_echo "❌ ERROR: Could not get caller address for profile: $profile"
        rm -f "$temp_file"
        return 1
    fi
    
    # Call the Move entry function
    if [ -n "$log_file" ]; then
        aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::list_all_solvers" \
            > "$temp_file" 2>&1
        local exit_code=$?
        cat "$temp_file" | tee -a "$log_file" > /dev/null
    else
        aptos move run --profile "$profile" --assume-yes \
            --function-id "0x${chain_address}::solver_registry::list_all_solvers" \
            > "$temp_file" 2>&1
        local exit_code=$?
    fi
    
    if [ $exit_code -ne 0 ]; then
        log_and_echo "❌ ERROR: Failed to call list_all_solvers function"
        if [ -n "$log_file" ]; then
            log_and_echo "   Log file contents:"
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
            cat "$temp_file"
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
        fi
        rm -f "$temp_file"
        return 1
    fi
    
    # Extract transaction hash from output
    local tx_hash=$(grep -i "transaction hash" "$temp_file" | head -1 | awk '{print $NF}' | tr -d '\n' || echo "")
    
    if [ -z "$tx_hash" ]; then
        # Try alternative format
        tx_hash=$(grep -oE '[0-9a-f]{64}' "$temp_file" | head -1 || echo "")
    fi
    
    # Wait for transaction to be processed
    sleep 2
    
    # Query events from the specific transaction
    local events=""
    if [ -n "$tx_hash" ]; then
        local tx_result=$(curl -s "${rpc_url}/v1/transactions/by_hash/${tx_hash}" 2>/dev/null)
        events=$(echo "$tx_result" | jq -r '.events[]? | select(.type | contains("SolverRegistered"))' 2>/dev/null)
    fi
    
    # Fallback: query from account's latest transaction if tx_hash not found
    if [ -z "$events" ] || [ "$events" = "null" ]; then
        local tx_result=$(curl -s "${rpc_url}/v1/accounts/${caller_address}/transactions?limit=1" 2>/dev/null)
        events=$(echo "$tx_result" | jq -r '.[0].events[]? | select(.type | contains("SolverRegistered"))' 2>/dev/null)
    fi
    
    rm -f "$temp_file"
    
    if [ -z "$events" ] || [ "$events" = "null" ]; then
        log_and_echo "   No solvers registered in the registry"
        return 0
    fi
    
    # Count solvers (events with non-empty public_key indicate registered solvers)
    local solver_count=$(echo "$events" | jq -s '[.[] | select(.data.public_key != null and (.data.public_key | length) > 0)] | length' 2>/dev/null)
    
    if [ "$solver_count" = "0" ] || [ -z "$solver_count" ]; then
        log_and_echo "   No solvers registered in the registry"
        return 0
    fi
    
    log_and_echo "   Found ${solver_count} registered solver(s):"
    log_and_echo ""
    
    # Parse and display each solver
    echo "$events" | jq -s '[.[] | select(.data.public_key != null and (.data.public_key | length) > 0)]' 2>/dev/null | jq -c '.[]' 2>/dev/null | while IFS= read -r event; do
        local solver_addr=$(echo "$event" | jq -r '.data.solver // empty' 2>/dev/null)
        local public_key=$(echo "$event" | jq -r '.data.public_key // []' 2>/dev/null)
        local evm_addr=$(echo "$event" | jq -r '.data.connected_chain_evm_address.vec[0] // "None"' 2>/dev/null)
        local mvm_addr=$(echo "$event" | jq -r '.data.connected_chain_mvm_address.vec[0] // "None"' 2>/dev/null)
        local registered_at=$(echo "$event" | jq -r '.data.timestamp // 0' 2>/dev/null)
        
        if [ -n "$solver_addr" ] && [ "$solver_addr" != "null" ]; then
            log_and_echo "   Solver: ${solver_addr}"
            local pk_length=$(echo "$public_key" | jq 'length' 2>/dev/null || echo "0")
            log_and_echo "     Public Key: ${public_key:0:20}... (${pk_length} bytes)"
            if [ "$evm_addr" != "None" ] && [ "$evm_addr" != "null" ] && [ "$evm_addr" != "" ]; then
                log_and_echo "     Connected Chain EVM Address: ${evm_addr}"
            else
                log_and_echo "     Connected Chain EVM Address: None"
            fi
            if [ "$mvm_addr" != "None" ] && [ "$mvm_addr" != "null" ] && [ "$mvm_addr" != "" ]; then
                log_and_echo "     Connected Chain MVM Address: ${mvm_addr}"
            else
                log_and_echo "     Connected Chain MVM Address: None"
            fi
            log_and_echo "     Registered At: ${registered_at}"
            log_and_echo ""
        fi
    done
}
