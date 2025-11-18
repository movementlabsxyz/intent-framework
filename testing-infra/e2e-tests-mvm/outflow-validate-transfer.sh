#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "validate-outflow-transfer"
cd "$PROJECT_ROOT"

log ""
log "🔍 OUTFLOW TRANSFER VALIDATION"
log "================================"
log ""

# Load transaction hash and intent_id from previous step
TRANSFER_INFO_FILE="${PROJECT_ROOT}/.test-data/outflow-transfer-info.txt"

if [ ! -f "$TRANSFER_INFO_FILE" ]; then
    log_and_echo "❌ ERROR: Transfer info file not found at $TRANSFER_INFO_FILE"
    log_and_echo "   Please run submit-outflow-solver-transfer.sh first"
    exit 1
fi

# Source the file to load variables
source "$TRANSFER_INFO_FILE"

if [ -z "$CONNECTED_CHAIN_TX_HASH" ]; then
    log_and_echo "❌ ERROR: CONNECTED_CHAIN_TX_HASH not found in transfer info file"
    exit 1
fi

if [ -z "$INTENT_ID" ]; then
    log_and_echo "❌ ERROR: INTENT_ID not found in transfer info file"
    exit 1
fi

log "📋 Transaction Information:"
log "   Intent ID: $INTENT_ID"
log "   Transaction Hash: $CONNECTED_CHAIN_TX_HASH"
log "   Chain Type: mvm (Move VM)"
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

# Prepare JSON request payload
REQUEST_PAYLOAD=$(cat <<EOF
{
  "transaction_hash": "$CONNECTED_CHAIN_TX_HASH",
  "chain_type": "mvm",
  "intent_id": "$INTENT_ID"
}
EOF
)

log ""
log "📤 Sending validation request to verifier..."
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

# Save approval signature to file for next step
APPROVAL_INFO_FILE="${PROJECT_ROOT}/.test-data/outflow-approval-info.txt"
mkdir -p "${PROJECT_ROOT}/.test-data"
echo "APPROVAL_SIGNATURE=$APPROVAL_SIGNATURE" > "$APPROVAL_INFO_FILE"
echo "SIGNATURE_TYPE=$SIGNATURE_TYPE" >> "$APPROVAL_INFO_FILE"
echo "INTENT_ID=$INTENT_ID" >> "$APPROVAL_INFO_FILE"
echo "TRANSACTION_HASH=$CONNECTED_CHAIN_TX_HASH" >> "$APPROVAL_INFO_FILE"

log "   ✅ Approval info saved to $APPROVAL_INFO_FILE"

log ""
log "🎉 OUTFLOW TRANSFER VALIDATION COMPLETE!"
log "========================================="
log ""
log "✅ Steps completed successfully:"
log "   1. Verifier queried connected chain transaction"
log "   2. Transaction validated against intent requirements"
log "   3. Approval signature generated for hub fulfillment"
log ""
log "📋 Validation Details:"
log "   Intent ID: $INTENT_ID"
log "   Transaction Hash: $CONNECTED_CHAIN_TX_HASH"
log "   Validation Result: VALID"
log "   Signature Type: $SIGNATURE_TYPE"
log "   Approval Signature: ${APPROVAL_SIGNATURE:0:40}..."
log ""
log "➡️  Next Step:"
log "   Run submit-outflow-hub-fulfillment.sh to fulfill the hub intent"
log "   using the approval signature"

log_and_echo ""
log_and_echo "✅ Validation complete"

