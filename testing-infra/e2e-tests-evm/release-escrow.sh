#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "release-escrow-evm"
cd "$PROJECT_ROOT"

log "🔓 EVM ESCROW RELEASE"
log "====================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

log "This script will:"
log "  1. Start the trusted verifier service"
log "  2. Monitor events on Chain 1 (hub) for intents and fulfillments"
log "  3. When fulfillment detected, create ECDSA signature"
log "  4. Release escrow on Chain 3 (EVM)"
log ""

# Start verifier (function handles stopping existing, starting, health checks, and initial polling wait)
start_verifier "$LOG_DIR/verifier-evm.log"

log ""

# Get EVM escrow contract address
cd evm-intent-framework
ESCROW_ADDRESS=$(grep -i "IntentEscrow deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-contract"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
cd ..

if [ -z "$ESCROW_ADDRESS" ]; then
    log_and_echo "❌ Could not find escrow contract address"
    exit 1
fi

log "   Escrow contract address: $ESCROW_ADDRESS"

# Get USDxyz token address from chain-info.env
if [ -f "$PROJECT_ROOT/tmp/chain-info.env" ]; then
    source "$PROJECT_ROOT/tmp/chain-info.env"
    USDXYZ_ADDRESS="$USDXYZ_EVM_ADDRESS"
fi
if [ -z "$USDXYZ_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not find USDxyz token address"
    exit 1
fi
log "   USDxyz token address: $USDXYZ_ADDRESS"

# Get Solver's EVM address
SOLVER_EVM_ADDRESS=$(get_hardhat_account_address "2")

# ============================================================================
# SECTION 1.5: CAPTURE INITIAL BALANCES (for final validation)
# ============================================================================
log ""
log "📊 Capturing initial balances for validation..."

# Note: Requester's balance on Chain 1 is validated in inflow-fulfill-hub-intent.sh

# Get Solver's initial USDxyz balance on EVM Chain 3
cd evm-intent-framework
SOLVER_CHAIN3_USDXYZ_INIT_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' ACCOUNT='$SOLVER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1)
SOLVER_CHAIN3_USDXYZ_INIT=$(echo "$SOLVER_CHAIN3_USDXYZ_INIT_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
cd ..

if [ -z "$SOLVER_CHAIN3_USDXYZ_INIT" ]; then
    log_and_echo "   ⚠️  WARNING: Failed to get Solver's initial USDxyz balance on Chain 3 (EVM)"
    log_and_echo "   Balance output: $SOLVER_CHAIN3_USDXYZ_INIT_OUTPUT"
    SOLVER_CHAIN3_USDXYZ_INIT="0"
fi

log "   Initial balances:"
log "      Solver Chain 3 USDxyz: $SOLVER_CHAIN3_USDXYZ_INIT"

# Track released escrows to avoid duplicate attempts
RELEASED_ESCROWS=""

# Function to check for new approvals and release escrows
check_and_release_escrows() {
    APPROVALS_RESPONSE=$(curl -s "http://127.0.0.1:3333/approvals")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    APPROVALS_SUCCESS=$(echo "$APPROVALS_RESPONSE" | jq -r '.success' 2>/dev/null)
    if [ "$APPROVALS_SUCCESS" != "true" ]; then
        return 1
    fi
    
    # Extract approvals array
    APPROVALS_COUNT=$(echo "$APPROVALS_RESPONSE" | jq -r '.data | length' 2>/dev/null || echo "0")
    
    if [ "$APPROVALS_COUNT" = "0" ]; then
        return 0
    fi
    
    # Process each approval
    for i in $(seq 0 $((APPROVALS_COUNT - 1))); do
        ESCROW_ID=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].escrow_id" 2>/dev/null | tr -d '\n\r\t ')
        INTENT_ID=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].intent_id" 2>/dev/null | tr -d '\n\r\t ')
        SIGNATURE_BASE64=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].signature" 2>/dev/null | tr -d '\n\r\t ')
        
        if [ -z "$ESCROW_ID" ] || [ "$ESCROW_ID" = "null" ]; then
            continue
        fi
        
        # Skip if already released
        if [[ "$RELEASED_ESCROWS" == *"$ESCROW_ID"* ]]; then
            continue
        fi
        
        log ""
        log "   📦 New approval found for escrow: $ESCROW_ID"
        log "   🔓 Releasing escrow on EVM chain..."
        
        # Convert intent_id to EVM format
        INTENT_ID_EVM=$(convert_intent_id_to_evm "$INTENT_ID")
        
        # Convert signature from base64 to hex for EVM
        # The verifier provides ECDSA signature as base64-encoded bytes (65 bytes: r || s || v)
        SIGNATURE_HEX=$(echo "$SIGNATURE_BASE64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')
        
        if [ -z "$SIGNATURE_HEX" ]; then
            log "   ❌ Failed to decode signature"
            continue
        fi
        
        # Signature should be 130 hex chars (65 bytes * 2)
        if [ ${#SIGNATURE_HEX} -ne 130 ]; then
            log "   ❌ Invalid signature length: expected 130 hex chars, got ${#SIGNATURE_HEX}"
            continue
        fi
        
        # Get Solver's balance before claiming (to verify funds were received)
        log "   - Getting Solver's Chain 3 balance before claim..."
        cd evm-intent-framework
        SOLVER_CHAIN3_ETH_BEFORE_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
        SOLVER_CHAIN3_ETH_BEFORE=$(echo "$SOLVER_CHAIN3_ETH_BEFORE_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
        cd ..
        
        if [ -z "$SOLVER_CHAIN3_ETH_BEFORE" ]; then
            log_and_echo "   ❌ ERROR: Failed to get Solver's Chain 3 balance before claim"
            log_and_echo "   Balance output: $SOLVER_CHAIN3_ETH_BEFORE_OUTPUT"
            exit 1
        fi
        
        log "   - Solver's Chain 3 balance before claim: $SOLVER_CHAIN3_ETH_BEFORE wei"
        
        # Submit escrow release transaction on EVM
        cd evm-intent-framework
        
        log "   - Calling IntentEscrow.claim() on EVM..."
        CLAIM_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ESCROW_ADDRESS='$ESCROW_ADDRESS' INTENT_ID_EVM='$INTENT_ID_EVM' SIGNATURE_HEX='$SIGNATURE_HEX' npx hardhat run scripts/claim-escrow.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
        
        TX_EXIT_CODE=$?
        cd ..
        
        if [ $TX_EXIT_CODE -ne 0 ]; then
            log_and_echo "   ❌ ERROR: Failed to release escrow on EVM chain"
            log_and_echo "   Claim output: $CLAIM_OUTPUT"
            log_and_echo "   Log file contents:"
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
            cat "$LOG_FILE"
            log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
            exit 1
        fi
        
        # Verify claim succeeded by checking for success message
        if ! echo "$CLAIM_OUTPUT" | grep -qi "Escrow released successfully"; then
            log_and_echo "   ❌ ERROR: Escrow claim did not complete successfully"
            log_and_echo "   Claim output: $CLAIM_OUTPUT"
            log_and_echo "   Expected to see 'Escrow released successfully' in output"
            exit 1
        fi
        
        # Wait a bit for transaction to be processed
        sleep 2
        
        # Get Solver's balance after claiming (to verify funds were received)
        log "   - Getting Solver's Chain 3 balance after claim..."
        cd evm-intent-framework
        SOLVER_CHAIN3_ETH_AFTER_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
        SOLVER_CHAIN3_ETH_AFTER=$(echo "$SOLVER_CHAIN3_ETH_AFTER_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
        cd ..
        
        if [ -z "$SOLVER_CHAIN3_ETH_AFTER" ]; then
            log_and_echo "   ❌ ERROR: Failed to get Solver's Chain 3 balance after claim"
            log_and_echo "   Balance output: $SOLVER_CHAIN3_ETH_AFTER_OUTPUT"
            exit 1
        fi
        
        log "   - Solver's Chain 3 balance after claim: $SOLVER_CHAIN3_ETH_AFTER wei"
        
        # Calculate balance increase
        # Expected: Solver should receive 1 ETH (matches request-intent offered_amount, minus gas fees)
        EXPECTED_AMOUNT_WEI="1000000000000000000"  # 1 ETH (matches request-intent offered_amount)
        CHAIN3_ETH_INCREASE=$(echo "$SOLVER_CHAIN3_ETH_AFTER $SOLVER_CHAIN3_ETH_BEFORE" | awk '{print $1 - $2}')
        
        log "   - Balance increase: $CHAIN3_ETH_INCREASE wei"
        log "   - Expected: ~$EXPECTED_AMOUNT_WEI wei (matches request-intent offered_amount, minus gas)"
        
        # Check if balance increased by at least 99% of expected (allowing for gas fees)
        MIN_EXPECTED=$(echo "$EXPECTED_AMOUNT_WEI" | awk '{print int($1 * 0.99)}')
        
        # Use awk for numeric comparison
        SUFFICIENT_INCREASE=$(echo "$CHAIN3_ETH_INCREASE $MIN_EXPECTED" | awk '{if ($1 >= $2) print "1"; else print "0"}')
        
        if [ "$SUFFICIENT_INCREASE" = "0" ] || [ -z "$CHAIN3_ETH_INCREASE" ] || [ "$CHAIN3_ETH_INCREASE" = "0" ]; then
            log_and_echo "   ❌ ERROR: Solver did not receive the escrow funds!"
            log_and_echo "   Solver's Chain 3 balance before: $SOLVER_CHAIN3_ETH_BEFORE wei"
            log_and_echo "   Solver's Chain 3 balance after:  $SOLVER_CHAIN3_ETH_AFTER wei"
            log_and_echo "   Balance increase:    $CHAIN3_ETH_INCREASE wei"
            log_and_echo "   Expected increase:   ~$EXPECTED_AMOUNT_WEI wei (matches request-intent offered_amount)"
            log_and_echo "   Minimum expected:     $MIN_EXPECTED wei (99% of escrow amount)"
            log_and_echo "   Escrow release FAILED - Solver did not receive funds!"
            exit 1
        fi
        
        log "   ✅ Escrow released successfully on EVM chain!"
        log "   ✅ Solver received $CHAIN3_ETH_INCREASE wei (expected ~$EXPECTED_AMOUNT_WEI wei)"
        RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
    done
}

log ""
log "⏳ Polling verifier for approvals..."
log "   Verifier API: http://127.0.0.1:3333/approvals"
log ""

# Poll for approvals a few times before script exits
log "   - Checking for approvals (will check 10 times with 3 second intervals)..."
for i in {1..10}; do
    sleep 3
    check_and_release_escrows
done

log ""
# Check if any escrows were released
if [ -z "$RELEASED_ESCROWS" ]; then
    log_and_echo "❌ ERROR: No escrows were released!"
    log_and_echo "   The verifier may not have approved the escrow, or the claim failed"
    log ""
    log "🔍 Diagnostic Information:"
    log "========================================"
    
    # Check what events the verifier has cached
    log ""
    log "   Verifier Events:"
    EVENTS_RESPONSE=$(curl -s "http://127.0.0.1:3333/events" 2>/dev/null)
    if [ $? -eq 0 ]; then
        ESCROW_COUNT=$(echo "$EVENTS_RESPONSE" | jq -r '.data.escrow_events | length' 2>/dev/null || echo "0")
        FULFILLMENT_COUNT=$(echo "$EVENTS_RESPONSE" | jq -r '.data.fulfillment_events | length' 2>/dev/null || echo "0")
        INTENT_COUNT=$(echo "$EVENTS_RESPONSE" | jq -r '.data.intent_events | length' 2>/dev/null || echo "0")
        
        log "      Escrow events cached: $ESCROW_COUNT"
        log "      Fulfillment events cached: $FULFILLMENT_COUNT"
        log "      Intent events cached: $INTENT_COUNT"
        
        if [ "$ESCROW_COUNT" != "0" ]; then
            log ""
            log "      Escrow events:"
            echo "$EVENTS_RESPONSE" | jq -r '.data.escrow_events[] | "         escrow_id: \(.escrow_id), intent_id: \(.intent_id), chain: \(.chain)"' 2>/dev/null || log "         (Unable to parse)"
        fi
        
        if [ "$FULFILLMENT_COUNT" != "0" ]; then
            log ""
            log "      Fulfillment events:"
            echo "$EVENTS_RESPONSE" | jq -r '.data.fulfillment_events[] | "         intent_id: \(.intent_id), solver: \(.solver), chain: \(.chain)"' 2>/dev/null || log "         (Unable to parse)"
        fi
    else
        log "      Failed to query verifier events endpoint"
    fi
    
    # Check what approvals the verifier has
    log ""
    log "   Verifier Approvals:"
    APPROVALS_RESPONSE=$(curl -s "http://127.0.0.1:3333/approvals" 2>/dev/null)
    if [ $? -eq 0 ]; then
        APPROVAL_COUNT=$(echo "$APPROVALS_RESPONSE" | jq -r '.data | length' 2>/dev/null || echo "0")
        log "      Approvals cached: $APPROVAL_COUNT"
        if [ "$APPROVAL_COUNT" != "0" ]; then
            log ""
            log "      Approval details:"
            echo "$APPROVALS_RESPONSE" | jq -r '.data[] | "         escrow_id: \(.escrow_id), intent_id: \(.intent_id), timestamp: \(.timestamp)"' 2>/dev/null || log "         (Unable to parse)"
        fi
    else
        log "      Failed to query verifier approvals endpoint"
    fi
    
    log ""
    log "   Verifier log:"
    log "   + + + + + + + + + + + + + + + + + + + +"
    cat "$VERIFIER_LOG" 2>/dev/null || log "      (Log file not found)"
    log "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
fi

log "✅ Escrow release monitoring complete!"
log "   Released escrows: $RELEASED_ESCROWS"
log ""

# ============================================================================
# SECTION: FINAL BALANCE VALIDATION
# ============================================================================
log ""
log "🔍 Validating final balances after inflow flow..."
log "================================================"
log "   - Waiting for transactions to be fully processed..."
sleep 5

# Get final balances
# Note: Requester's balance on Chain 1 is validated in inflow-fulfill-hub-intent.sh

cd evm-intent-framework
SOLVER_CHAIN3_USDXYZ_FINAL_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' ACCOUNT='$SOLVER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1)
SOLVER_CHAIN3_USDXYZ_FINAL=$(echo "$SOLVER_CHAIN3_USDXYZ_FINAL_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
cd ..

if [ -z "$SOLVER_CHAIN3_USDXYZ_FINAL" ]; then
    log_and_echo "   ❌ ERROR: Failed to get Solver's final USDxyz balance on Chain 3 (EVM)"
    log_and_echo "   Balance output: $SOLVER_CHAIN3_USDXYZ_FINAL_OUTPUT"
    exit 1
fi

# For inflow flow:
# - Solver on EVM Chain 3 should have received 1000 USDxyz (matches request-intent offered_amount) from escrow release
# Note: Requester's balance on Chain 1 is validated in inflow-fulfill-hub-intent.sh (hub intent fulfillment)

SOLVER_CHAIN3_USDXYZ_EXPECTED="100000000000"  # 1000 USDxyz (8 decimals, matches request-intent offered_amount)

# Calculate balance increase for Solver on EVM Chain 3
SOLVER_CHAIN3_USDXYZ_GAIN=$((SOLVER_CHAIN3_USDXYZ_FINAL - SOLVER_CHAIN3_USDXYZ_INIT))

# Check if escrow was released (Solver on EVM Chain 3 should have received funds)
if [ "$SOLVER_CHAIN3_USDXYZ_GAIN" -lt "$SOLVER_CHAIN3_USDXYZ_EXPECTED" ]; then
    log_and_echo "❌ ERROR: Solver on EVM Chain 3 USDxyz balance did not increase by expected amount!"
    log_and_echo "   Initial balance: $SOLVER_CHAIN3_USDXYZ_INIT"
    log_and_echo "   Final balance: $SOLVER_CHAIN3_USDXYZ_FINAL"
    log_and_echo "   Balance increase: $SOLVER_CHAIN3_USDXYZ_GAIN"
    log_and_echo "   Expected increase: $SOLVER_CHAIN3_USDXYZ_EXPECTED (1000 USDxyz)"
    log_and_echo "   This indicates the escrow was not released or funds were not received"
    exit 1
fi

log "   ✅ Final balances validated:"
log "      Solver Chain 3 USDxyz: $SOLVER_CHAIN3_USDXYZ_INIT → $SOLVER_CHAIN3_USDXYZ_FINAL (+$SOLVER_CHAIN3_USDXYZ_GAIN, escrow released)"

log ""
log "📝 Useful commands:"
log "   View approvals:  curl -s http://127.0.0.1:3333/approvals | jq"
log "   View events:    curl -s http://127.0.0.1:3333/events | jq"
log "   Health check:   curl -s http://127.0.0.1:3333/health"

