#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "outflow-validate-and-fulfill"
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
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Intent ID:               $INTENT_ID"
log "   Hub Request Intent Address: $HUB_INTENT_ADDRESS"
log "   Transaction Hash:        $CONNECTED_CHAIN_TX_HASH"
log "   Chain Type:              mvm (Move VM)"

log ""
log "   - Checking if verifier is running..."
if ! curl -s "http://127.0.0.1:3333/health" > /dev/null 2>&1; then
    log_and_echo "❌ ERROR: Verifier is not running"
    log_and_echo "   Please start the verifier service first"
    log_and_echo "   You can start it by running: ./testing-infra/e2e-tests-mvm/release-escrow.sh"
    exit 1
fi
log "   ✅ Verifier is running"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_hub
log_and_echo ""

BOB_INITIAL_BALANCE=$(aptos account balance --profile bob-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
log "   Bob Chain 1 initial balance: $BOB_INITIAL_BALANCE Octas"

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "📤 Validating transfer with verifier..."
log "======================================="

REQUEST_PAYLOAD=$(cat <<EOF
{
  "transaction_hash": "$CONNECTED_CHAIN_TX_HASH",
  "chain_type": "mvm",
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
REASON=$(echo "$RESPONSE" | jq -r '.data.validation.reason // empty' 2>/dev/null)

if [ "$VALID" != "true" ]; then
    log_and_echo "❌ ERROR: Transaction validation failed"
    log_and_echo "   Validation result: $VALID"
    if [ -n "$REASON" ]; then
        log_and_echo "   Reason: $REASON"
    fi
    log_and_echo "   Full response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

log "   ✅ Transaction validation passed!"
if [ -n "$REASON" ]; then
    log "   Reason: $REASON"
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
log "🔓 Fulfilling hub request intent with verifier signature..."
log "========================================================="

INTENT_OBJECT_ADDRESS="$HUB_INTENT_ADDRESS"

if [ -z "$INTENT_OBJECT_ADDRESS" ] || [ "$INTENT_OBJECT_ADDRESS" = "null" ]; then
    log_and_echo "❌ ERROR: Could not get intent object address"
    exit 1
fi

SIGNATURE_HEX="${APPROVAL_SIGNATURE#0x}"

log "   - Fulfilling intent at: $INTENT_OBJECT_ADDRESS"
log "   - Calling fulfill_outflow_request_intent with verifier signature"

aptos move run --profile bob-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::fulfill_outflow_request_intent" \
    --args "address:$INTENT_OBJECT_ADDRESS" "hex:$SIGNATURE_HEX" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Solver (Bob) successfully fulfilled the outflow request intent!"

    sleep 2

    log "     - Verifying solver (Bob) received locked tokens..."
    BOB_FINAL_BALANCE=$(aptos account balance --profile bob-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    log "     Bob Chain 1 final balance: $BOB_FINAL_BALANCE Octas"

    BALANCE_INCREASE=$((BOB_FINAL_BALANCE - BOB_INITIAL_BALANCE))
    OFFERED_AMOUNT=100000000
    EXPECTED_MIN_AMOUNT=$((OFFERED_AMOUNT - 1000000))

    if [ "$BALANCE_INCREASE" -ge "$EXPECTED_MIN_AMOUNT" ]; then
        log "     ✅ Solver (Bob) received locked tokens: +$BALANCE_INCREASE Octas (expected ~$OFFERED_AMOUNT minus gas)"
    else
        log_and_echo "❌ ERROR: Solver (Bob)'s balance increase is less than expected"
        log_and_echo "   Balance increase: $BALANCE_INCREASE Octas"
        log_and_echo "   Expected minimum: $EXPECTED_MIN_AMOUNT Octas"
        exit 1
    fi

    log_and_echo "✅ Outflow request intent fulfilled"
else
    log_and_echo "❌ Outflow request intent fulfillment failed!"
    log_and_echo "   Log file contents:"
    cat "$LOG_FILE"
    exit 1
fi

# ============================================================================
# SECTION 6: FINAL SUMMARY
# ============================================================================
log ""
display_balances_hub
display_balances_connected_apt
log_and_echo ""

log ""
log "🎉 OUTFLOW VALIDATION AND FULFILLMENT COMPLETE!"
log "=============================================="
log ""
log "✅ Steps completed successfully:"
log "   1. Verifier queried connected chain transaction"
log "   2. Transaction validated against intent requirements"
log "   3. Approval signature generated for hub fulfillment"
log "   4. Solver (Bob) fulfilled hub request intent with verifier signature"
log "   5. Locked tokens released to solver (Bob) on hub chain"
log ""
log "📋 Details:"
log "   Intent ID: $INTENT_ID"
log "   Hub Request Intent Address: $HUB_INTENT_ADDRESS"
log "   Transaction Hash: $CONNECTED_CHAIN_TX_HASH"
log "   Validation Result: VALID"
log "   Signature Type: $SIGNATURE_TYPE"
log "   Solver (Bob)'s balance increase: $BALANCE_INCREASE Octas"
log ""
log "📖 Outflow Request Intent Summary:"
log "   1. Requester (Alice) created outflow request intent on hub chain (locked 100000000 tokens)"
log "   2. Solver (Bob) transferred 100000000 tokens to requester (Alice) on connected chain"
log "   3. Verifier validated the connected chain transfer"
log "   4. Solver (Bob) fulfilled hub request intent with verifier signature"
log "   5. Solver (Bob) received locked tokens as reward on hub chain"
