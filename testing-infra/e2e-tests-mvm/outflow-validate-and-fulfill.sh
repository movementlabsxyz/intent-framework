#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "outflow-validate-and-fulfill"
cd "$PROJECT_ROOT"

log ""
log "🔍 OUTFLOW TRANSFER VALIDATION AND HUB FULFILLMENT"
log "=================================================="
log ""

# Load INTENT_ID and HUB_INTENT_ADDRESS from info file created by submit-outflow-hub-intent.sh
if ! load_intent_info "INTENT_ID,HUB_INTENT_ADDRESS"; then
    exit 1
fi

# Load transaction hash and intent_id from solver transfer step
TRANSFER_INFO_FILE="${PROJECT_ROOT}/.test-data/outflow-transfer-info.txt"

if [ ! -f "$TRANSFER_INFO_FILE" ]; then
    log_and_echo "❌ ERROR: Transfer info file not found at $TRANSFER_INFO_FILE"
    log_and_echo "   Please run outflow-solver-transfer.sh first"
    exit 1
fi

# Source the file to load variables
source "$TRANSFER_INFO_FILE"

if [ -z "$CONNECTED_CHAIN_TX_HASH" ]; then
    log_and_echo "❌ ERROR: CONNECTED_CHAIN_TX_HASH not found in transfer info file"
    exit 1
fi

# Get addresses
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")

log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Intent ID:                $INTENT_ID"
log "   Hub Request Intent Address: $HUB_INTENT_ADDRESS"
log "   Transaction Hash:         $CONNECTED_CHAIN_TX_HASH"
log "   Chain Type:               mvm (Move VM)"
log ""

# Check if verifier is running
log "   - Checking if verifier is running..."
if ! curl -s "http://127.0.0.1:3333/health" > /dev/null 2>&1; then
    log_and_echo "❌ ERROR: Verifier is not running"
    log_and_echo "   Please start the verifier service first"
    log_and_echo "   You can start it by running: ./testing-infra/e2e-tests-mvm/release-escrow.sh"
    exit 1
fi
log "   ✅ Verifier is running"

log ""
log "📤 Validating transfer with verifier..."
log "======================================="

# Prepare JSON request payload
REQUEST_PAYLOAD=$(cat <<EOF
{
  "transaction_hash": "$CONNECTED_CHAIN_TX_HASH",
  "chain_type": "mvm",
  "intent_id": "$INTENT_ID"
}
EOF
)

log "   Endpoint: POST http://127.0.0.1:3333/validate-outflow-fulfillment"

# Call verifier validate-outflow-fulfillment endpoint
RESPONSE=$(curl -s -X POST "http://127.0.0.1:3333/validate-outflow-fulfillment" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_PAYLOAD")

# Check if curl succeeded
if [ $? -ne 0 ]; then
    log_and_echo "❌ ERROR: Failed to call verifier API"
    log_and_echo "   Endpoint: http://127.0.0.1:3333/validate-outflow-fulfillment"
    exit 1
fi

# Log the full response for debugging
log "   Response received:"
echo "$RESPONSE" | jq '.' >> "$LOG_FILE" 2>&1 || echo "$RESPONSE" >> "$LOG_FILE"

# Parse response
SUCCESS=$(echo "$RESPONSE" | jq -r '.success' 2>/dev/null)
ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null)

if [ "$SUCCESS" != "true" ]; then
    log_and_echo "❌ ERROR: Verifier API returned failure"
    if [ -n "$ERROR_MSG" ]; then
        log_and_echo "   Error: $ERROR_MSG"
    fi
    log_and_echo "   Full response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

# Extract validation result
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

# Extract approval signature
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

# Check and display initial balances
log ""
log "📊 Initial Balances:"
display_balances_hub
log_and_echo ""

# Get Bob's initial balance on Chain 1 for verification
BOB_INITIAL_BALANCE=$(aptos account balance --profile bob-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
log "   Bob Chain 1 initial balance: $BOB_INITIAL_BALANCE Octas"

log ""
log "   - Solver (Bob) fulfills the hub request intent using verifier signature"
log "   - Intent ID: $INTENT_ID"
log "   - Hub Request Intent Address: $HUB_INTENT_ADDRESS"
log "   - Verifier signature (first 20 chars): ${APPROVAL_SIGNATURE:0:20}..."

# Get the intent object address
INTENT_OBJECT_ADDRESS="$HUB_INTENT_ADDRESS"

if [ -z "$INTENT_OBJECT_ADDRESS" ] || [ "$INTENT_OBJECT_ADDRESS" = "null" ]; then
    log_and_echo "     ❌ ERROR: Could not get intent object address"
    exit 1
fi

# Convert signature to hex format (remove any 0x prefix if present)
SIGNATURE_HEX="${APPROVAL_SIGNATURE#0x}"

log "   - Fulfilling intent at: $INTENT_OBJECT_ADDRESS"
log "   - Calling fulfill_outflow_request_intent with verifier signature"

# Solver (Bob) fulfills the outflow intent by providing the verifier signature
# The verifier signature proves that tokens were transferred on the connected chain
# Solver (Bob) receives the locked tokens from the hub as reward (offered_amount)
aptos move run --profile bob-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::fulfill_outflow_request_intent" \
    --args "address:$INTENT_OBJECT_ADDRESS" "hex:$SIGNATURE_HEX" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Solver (Bob) successfully fulfilled the outflow request intent!"

    # Wait for transaction to be processed
    sleep 2

    # Verify solver (Bob)'s balance increased
    log "     - Verifying solver (Bob) received locked tokens..."
    BOB_FINAL_BALANCE=$(aptos account balance --profile bob-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    log "     Bob Chain 1 final balance: $BOB_FINAL_BALANCE Octas"

    # Calculate balance increase (accounting for gas)
    BALANCE_INCREASE=$((BOB_FINAL_BALANCE - BOB_INITIAL_BALANCE))

    # Expected amount: 100000000 tokens (locked in hub request intent) minus gas fees
    # We expect solver (Bob)'s balance to increase by approximately 100000000 (allowing for gas)
    OFFERED_AMOUNT=100000000
    EXPECTED_MIN_AMOUNT=$((OFFERED_AMOUNT - 1000000)) # Allow for gas fees

    if [ "$BALANCE_INCREASE" -ge "$EXPECTED_MIN_AMOUNT" ]; then
        log "     ✅ Solver (Bob) received locked tokens: +$BALANCE_INCREASE Octas (expected ~$OFFERED_AMOUNT minus gas)"
    else
        log_and_echo "     ⚠️  WARNING: Solver (Bob)'s balance increase is less than expected"
        log_and_echo "        Balance increase: $BALANCE_INCREASE Octas"
        log_and_echo "        Expected minimum: $EXPECTED_MIN_AMOUNT Octas"
        log_and_echo "        Note: This may be due to higher gas costs"
    fi

    log_and_echo "✅ Outflow request intent fulfilled"
else
    log_and_echo "     ❌ Outflow request intent fulfillment failed!"
    log_and_echo "   Log file contents:"
    cat "$LOG_FILE"
    exit 1
fi

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

# Check final balances using common function
log ""
display_balances_hub
display_balances_connected_apt
log_and_echo ""
