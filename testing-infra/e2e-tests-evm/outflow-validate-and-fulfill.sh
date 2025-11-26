#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root and logging
setup_project_root
setup_logging "outflow-validate-and-fulfill-evm"
cd "$PROJECT_ROOT"

# ============================================================================
# SECTION 1: LOAD DEPENDENCIES
# ============================================================================
if ! load_intent_info "INTENT_ID,HUB_INTENT_ADDRESS"; then
    exit 1
fi

TRANSFER_INFO_FILE="${PROJECT_ROOT}/.test-data/outflow-transfer-info.txt"

if [ ! -f "$TRANSFER_INFO_FILE" ]; then
    log_and_echo "❌ ERROR: Transfer info file not found at $TRANSFER_INFO_FILE"
    log_and_echo "   Please run outflow-solver-transfer.sh first"
    exit 1
fi

source "$TRANSFER_INFO_FILE"

if [ -z "$CONNECTED_CHAIN_TX_HASH" ]; then
    log_and_echo "❌ ERROR: CONNECTED_CHAIN_TX_HASH not found in transfer info file"
    exit 1
fi

# ============================================================================
# SECTION 2: GET ADDRESSES AND CONFIGURATION
# ============================================================================
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")

# Get USDxyz EVM address
source "$PROJECT_ROOT/tmp/chain-info.env" 2>/dev/null || true
USDXYZ_ADDRESS="$USDXYZ_EVM_ADDRESS"

log ""
log "📋 Chain Information:"
log "   Hub Chain Module Address (Chain 1):     $CHAIN1_ADDRESS"
log "   Solver Chain 1 (hub):       $SOLVER_CHAIN1_ADDRESS"
log "   Intent ID:               $INTENT_ID"
log "   Hub Request-intent Address: $HUB_INTENT_ADDRESS"
log "   Transaction Hash:        $CONNECTED_CHAIN_TX_HASH"
log "   Chain Type:              evm (Ethereum Virtual Machine)"

log ""
log "   - Checking if verifier is running..."
if ! curl -s "http://127.0.0.1:3333/health" > /dev/null 2>&1; then
    log_and_echo "❌ ERROR: Verifier is not running"
    log_and_echo "   Please start the verifier service first"
    log_and_echo "   The verifier should be started in run-tests-outflow.sh before this script"
    exit 1
fi
log "   ✅ Verifier is running"

# Wait for verifier to poll and cache the request-intent
# The verifier polls every 2 seconds, so wait for it to discover the request-intent
log ""
log "   - Waiting for verifier to poll and cache request-intent..."
MAX_WAIT=30  # Maximum wait time in seconds (should be enough for several poll cycles)
WAIT_INTERVAL=2  # Check every 2 seconds (matches polling interval)
ELAPSED=0
INTENT_FOUND=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    EVENTS_RESPONSE=$(curl -s "http://127.0.0.1:3333/events" 2>/dev/null)
    # Normalize intent_id by removing 0x prefix and leading zeros for comparison
    NORMALIZED_INTENT_ID=$(echo "$INTENT_ID" | tr '[:upper:]' '[:lower:]' | sed 's/^0x//' | sed 's/^0*//')
    if [ $? -eq 0 ] && echo "$EVENTS_RESPONSE" | jq -e '.data.intent_events[] | select(.intent_id | ascii_downcase | gsub("^0x"; "") | gsub("^0+"; "") == "'"$NORMALIZED_INTENT_ID"'")' > /dev/null 2>&1; then
        INTENT_FOUND=true
        break
    fi
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ "$INTENT_FOUND" = true ]; then
    log "     ✅ Verifier has cached the request-intent"
else
    log_and_echo "❌ ERROR: Verifier did not cache the request-intent within ${MAX_WAIT} seconds"
    log_and_echo "   Intent ID: $INTENT_ID"
    log_and_echo "   Verifier events:"
    curl -s "http://127.0.0.1:3333/events" | jq '.data.intent_events' 2>/dev/null || log "   (Unable to query events)"
    exit 1
fi

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""

# Get USDxyz metadata for balance checks
TEST_TOKENS_CHAIN1_ADDRESS=$(get_profile_address "test-tokens-chain1")
SOLVER_CHAIN1_USDXYZ_INIT=$(get_usdxyz_balance "solver-chain1" "1" "0x$TEST_TOKENS_CHAIN1_ADDRESS")
log "   Solver Chain 1 initial USDxyz balance: $SOLVER_CHAIN1_USDXYZ_INIT USDxyz.10e8"

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "📤 Validating transfer with verifier..."
log "======================================="

REQUEST_PAYLOAD=$(cat <<EOF
{
  "transaction_hash": "$CONNECTED_CHAIN_TX_HASH",
  "chain_type": "evm",
  "intent_id": "$INTENT_ID"
}
EOF
)

log "   Endpoint: POST http://127.0.0.1:3333/validate-outflow-fulfillment"
log "   Request payload:"
echo "$REQUEST_PAYLOAD" | jq '.' 2>/dev/null || echo "$REQUEST_PAYLOAD" | while IFS= read -r line; do
    log "     $line"
done

RESPONSE=$(curl -s -X POST "http://127.0.0.1:3333/validate-outflow-fulfillment" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_PAYLOAD")

if [ $? -ne 0 ]; then
    log_and_echo "❌ ERROR: Failed to call verifier API"
    log_and_echo "   Endpoint: http://127.0.0.1:3333/validate-outflow-fulfillment"
    log_and_echo "   Request payload:"
    echo "$REQUEST_PAYLOAD" | jq '.' 2>/dev/null || echo "$REQUEST_PAYLOAD"
    exit 1
fi

log "   Response received:"
echo "$RESPONSE" | jq '.' >> "$LOG_FILE" 2>&1 || echo "$RESPONSE" >> "$LOG_FILE"

SUCCESS=$(echo "$RESPONSE" | jq -r '.success' 2>/dev/null)
ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null)

if [ "$SUCCESS" != "true" ]; then
    log_and_echo "❌ ERROR: Verifier API returned failure"
    if [ -n "$ERROR_MSG" ]; then
        log_and_echo "   Error: $ERROR_MSG"
    fi
    log_and_echo "   Request payload:"
    echo "$REQUEST_PAYLOAD" | jq '.' 2>/dev/null || echo "$REQUEST_PAYLOAD"
    log_and_echo "   Full response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

VALID=$(echo "$RESPONSE" | jq -r '.data.validation.valid' 2>/dev/null)
MESSAGE=$(echo "$RESPONSE" | jq -r '.data.validation.message // empty' 2>/dev/null)

if [ "$VALID" != "true" ]; then
    log_and_echo "❌ ERROR: Transaction validation failed"
    log_and_echo "   Validation result: $VALID"
    if [ -n "$MESSAGE" ]; then
        log_and_echo "   Message: $MESSAGE"
    fi
    
    # Output verifier logs for debugging
    log_and_echo ""
    log_and_echo "   Verifier logs (relevant errors and debug info):"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    
    VERIFIER_LOG_FILE=""
    if [ -n "$VERIFIER_LOG" ] && [ -f "$VERIFIER_LOG" ]; then
        VERIFIER_LOG_FILE="$VERIFIER_LOG"
    elif [ -f "$LOG_DIR/verifier-evm.log" ]; then
        VERIFIER_LOG_FILE="$LOG_DIR/verifier-evm.log"
    fi
    
    if [ -n "$VERIFIER_LOG_FILE" ]; then
        # First, show relevant error/debug lines
        log_and_echo "   Relevant error/debug lines:"
        grep -E "(ERROR|WARN|DEBUG|connected_chain_evm_address|get_solver_evm_address|SolverRegistry)" "$VERIFIER_LOG_FILE" | tail -50 | while IFS= read -r line; do
            log_and_echo "   $line"
        done || log_and_echo "   (No relevant error lines found)"
        
        log_and_echo ""
        log_and_echo "   Full verifier log:"
        cat "$VERIFIER_LOG_FILE" | while IFS= read -r line; do
            log_and_echo "   $line"
        done
    else
        log_and_echo "   (Verifier log file not found)"
        log_and_echo "   Tried: VERIFIER_LOG='$VERIFIER_LOG'"
        log_and_echo "   Tried: $LOG_DIR/verifier-evm.log"
    fi
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    log_and_echo ""
    
    # If the error is about solver registration, list all registered solvers
    if echo "$MESSAGE" | grep -qi "is not registered in hub chain solver registry"; then
        log_and_echo ""
        log_and_echo "   Available registered solvers:"
        list_all_solvers "solver-chain1" "$CHAIN1_ADDRESS" "$LOG_FILE"
    fi
    
    log_and_echo "   Full response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

log "   ✅ Transaction validation passed!"
if [ -n "$MESSAGE" ]; then
    log "   Message: $MESSAGE"
fi

APPROVAL_SIGNATURE=$(echo "$RESPONSE" | jq -r '.data.approval_signature.signature // empty' 2>/dev/null)
SIGNATURE_TYPE=$(echo "$RESPONSE" | jq -r '.data.approval_signature.signature_type // empty' 2>/dev/null)

if [ -z "$APPROVAL_SIGNATURE" ]; then
    log_and_echo "❌ ERROR: No approval signature in response"
    log_and_echo "   This is unexpected when validation passes"
    log_and_echo "   Full response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

log "   ✅ Approval signature received"
log "   Signature type: $SIGNATURE_TYPE"
log "   Signature (first 20 chars): ${APPROVAL_SIGNATURE:0:20}..."

log ""
log "🔓 Fulfilling hub request-intent with verifier signature..."
log "========================================================="

INTENT_OBJECT_ADDRESS="$HUB_INTENT_ADDRESS"

if [ -z "$INTENT_OBJECT_ADDRESS" ] || [ "$INTENT_OBJECT_ADDRESS" = "null" ]; then
    log_and_echo "❌ ERROR: Could not get intent object address"
    exit 1
fi

# Convert base64 signature to hex (verifier API returns base64-encoded Ed25519 signature)
SIGNATURE_HEX=$(echo "$APPROVAL_SIGNATURE" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')

if [ -z "$SIGNATURE_HEX" ]; then
    log_and_echo "❌ ERROR: Failed to decode signature from base64 to hex"
    log_and_echo "   Signature: ${APPROVAL_SIGNATURE:0:50}..."
    exit 1
fi

# Ed25519 signature should be 128 hex chars (64 bytes * 2)
if [ ${#SIGNATURE_HEX} -ne 128 ]; then
    log_and_echo "❌ ERROR: Invalid signature length: expected 128 hex chars (64 bytes), got ${#SIGNATURE_HEX}"
    log_and_echo "   Signature hex: ${SIGNATURE_HEX:0:50}..."
    exit 1
fi

log "   - Fulfilling intent at: $INTENT_OBJECT_ADDRESS"
log "   - Calling fulfill_outflow_request_intent with verifier signature"

aptos move run --profile solver-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::fulfill_outflow_request_intent" \
    --args "address:$INTENT_OBJECT_ADDRESS" "hex:$SIGNATURE_HEX" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Solver (Solver) successfully fulfilled the outflow request-intent!"

    sleep 2

    log "     - Verifying solver (Solver) received locked USDxyz tokens..."
    SOLVER_CHAIN1_USDXYZ_FINAL=$(get_usdxyz_balance "solver-chain1" "1" "0x$TEST_TOKENS_CHAIN1_ADDRESS")
    log "     Solver Chain 1 final USDxyz balance: $SOLVER_CHAIN1_USDXYZ_FINAL USDxyz.10e8"

    CHAIN1_USDXYZ_INCREASE=$((SOLVER_CHAIN1_USDXYZ_FINAL - SOLVER_CHAIN1_USDXYZ_INIT))
    OFFERED_AMOUNT=100000000  # 1 USDxyz = 100_000_000

    if [ "$CHAIN1_USDXYZ_INCREASE" -ge "$OFFERED_AMOUNT" ]; then
        log "     ✅ Solver (Solver) received locked USDxyz: +$CHAIN1_USDXYZ_INCREASE USDxyz.10e8 (expected $OFFERED_AMOUNT)"
    else
        log_and_echo "❌ ERROR: Solver (Solver) Chain 1 USDxyz balance increase is less than expected"
        log_and_echo "   Chain 1 USDxyz increase: $CHAIN1_USDXYZ_INCREASE USDxyz.10e8"
        log_and_echo "   Expected: $OFFERED_AMOUNT USDxyz.10e8"
        exit 1
    fi

    log_and_echo "✅ Outflow request-intent fulfilled"
else
    log_and_echo "❌ Outflow request-intent fulfillment failed!"
    log_and_echo "   Log file contents:"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    cat "$LOG_FILE"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
fi

# ============================================================================
# SECTION 6: FINAL SUMMARY
# ============================================================================
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""

log ""
log "🎉 OUTFLOW - VALIDATION AND FULFILLMENT COMPLETE!"
log "================================================="
log ""
log "✅ Steps completed successfully:"
log "   1. Verifier queried connected EVM chain transaction"
log "   2. Transaction validated against intent requirements"
log "   3. Approval signature generated for hub fulfillment"
log "   4. Solver (Solver) fulfilled hub request-intent with verifier signature"
log "   5. Locked tokens released to solver (Solver) on hub chain"
log ""
log "📋 Details:"
log "   Intent ID: $INTENT_ID"
log "   Hub Request-intent Address: $HUB_INTENT_ADDRESS"
log "   Transaction Hash: $CONNECTED_CHAIN_TX_HASH"
log "   Validation Result: VALID"
log "   Signature Type: $SIGNATURE_TYPE"
log "   Solver (Solver) Chain 1 USDxyz increase: $CHAIN1_USDXYZ_INCREASE USDxyz.10e8"
log ""
log "📖 Outflow Request-intent Summary:"
log "   1. Requester (Requester) created outflow request-intent on hub chain (locked 1 USDxyz)"
log "   2. Solver (Solver) transferred tokens to requester (Requester) on connected EVM chain (amount matches request-intent desired_amount)"
log "   3. Verifier validated the connected EVM chain transfer"
log "   4. Solver (Solver) fulfilled hub request-intent with verifier signature"
log "   5. Solver (Solver) received locked tokens as reward on hub chain"

