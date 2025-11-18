#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-outflow-hub-intent"
cd "$PROJECT_ROOT"

# Generate a random intent_id for the outflow intent
INTENT_ID="0x$(openssl rand -hex 32)"

# Move VM mode: CONNECTED_CHAIN_ID=2
CONNECTED_CHAIN_ID=2

# Get addresses
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
CHAIN2_ADDRESS=$(get_profile_address "intent-account-chain2")

# Get Alice and Bob addresses
ALICE_CHAIN1_ADDRESS=$(get_profile_address "alice-chain1")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")
ALICE_CHAIN2_ADDRESS=$(get_profile_address "alice-chain2")
BOB_CHAIN2_ADDRESS=$(get_profile_address "bob-chain2")

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Connected Chain (Chain 2): $CHAIN2_ADDRESS"
log "   Alice Chain 1 (hub):     $ALICE_CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Alice Chain 2 (connected): $ALICE_CHAIN2_ADDRESS"
log "   Bob Chain 2 (connected): $BOB_CHAIN2_ADDRESS"

# Load oracle public key from verifier config (base64 encoded, needs to be converted to hex)
# Use verifier_testing.toml for tests - required, panic if not found
VERIFIER_TESTING_CONFIG="${PROJECT_ROOT}/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

# Export config path for Rust code to use (if called)
export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

VERIFIER_PUBLIC_KEY_B64=$(grep "^public_key" "$VERIFIER_TESTING_CONFIG" | cut -d'"' -f2)

if [ -z "$VERIFIER_PUBLIC_KEY_B64" ]; then
    log_and_echo "❌ ERROR: Could not find public_key in verifier_testing.toml"
    log_and_echo "   The verifier public key is required for outflow intent creation."
    log_and_echo "   Please ensure verifier_testing.toml has a valid public_key field."
    exit 1
fi

# Convert base64 public key to hex (32 bytes)
VERIFIER_PUBLIC_KEY_HEX=$(echo "$VERIFIER_PUBLIC_KEY_B64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')

if [ -z "$VERIFIER_PUBLIC_KEY_HEX" ] || [ ${#VERIFIER_PUBLIC_KEY_HEX} -ne 64 ]; then
    log_and_echo "❌ ERROR: Invalid public key format in verifier_testing.toml"
    log_and_echo "   Expected: base64-encoded 32-byte Ed25519 public key"
    log_and_echo "   Got: $VERIFIER_PUBLIC_KEY_B64"
    log_and_echo "   Please ensure the public_key in verifier_testing.toml is valid base64 and decodes to 32 bytes (64 hex chars)."
    exit 1
fi

VERIFIER_PUBLIC_KEY="0x${VERIFIER_PUBLIC_KEY_HEX}"
log "   ✅ Loaded verifier public key from config (32 bytes)"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Verifier public key: $VERIFIER_PUBLIC_KEY"

# Check and display initial balances using common function
log ""
display_balances_hub
display_balances_connected_apt
log_and_echo ""

log ""
log "   Creating outflow request intent on hub chain..."
log "   - Requester (Alice) creates outflow request intent on Chain 1 (hub chain)"
log "   - Requester (Alice) locks 100000000 tokens on hub chain"
log "   - Requester (Alice) wants 100000000 tokens on connected chain (Chain 2)"
log "   - Using intent_id: $INTENT_ID"

# Get APT metadata addresses for both chains using helper function
log "   - Getting APT metadata addresses..."

# Get APT metadata on Chain 1 (hub)
log "     Getting APT metadata on Chain 1..."
APT_METADATA_CHAIN1=$(extract_apt_metadata "alice-chain1" "$CHAIN1_ADDRESS" "$ALICE_CHAIN1_ADDRESS" "1" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 1: $APT_METADATA_CHAIN1"
OFFERED_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"

# Get APT metadata on Chain 2 (connected chain)
log "     Getting APT metadata on Chain 2..."
APT_METADATA_CHAIN2=$(extract_apt_metadata "alice-chain2" "$CHAIN2_ADDRESS" "$ALICE_CHAIN2_ADDRESS" "2" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 2: $APT_METADATA_CHAIN2"
DESIRED_FA_METADATA_CHAIN2="$APT_METADATA_CHAIN2"

# Create outflow request intent on Chain 1 using fa_intent_outflow module
# NOTE: Outflow intents must be reserved. This requires:
# 1. Off-chain negotiation with solver (Bob)
# 2. Solver signs IntentToSign structure (BCS-encoded)
# 3. Pass solver address and signature to create_outflow_request_intent_entry
#
# For outflow intents:
# - offered tokens are on hub chain (Chain 1) - these tokens are locked
# - desired tokens are on connected chain (Chain 2)
#
log "   - Creating outflow request intent on Chain 1..."
log "     Offered FA metadata (hub): $OFFERED_FA_METADATA_CHAIN1"
log "     Desired FA metadata (connected): $DESIRED_FA_METADATA_CHAIN2"
log "     Solver (Bob) address: $BOB_CHAIN1_ADDRESS"
log "     Requester address on connected chain: $ALICE_CHAIN2_ADDRESS"
log "     Generating solver signature..."

# Generate solver signature using helper function
# For outflow intents: offered tokens are on hub chain (chain 1), desired tokens are on connected chain (2)
OFFERED_AMOUNT="100000000"
OFFERED_CHAIN_ID=1  # Hub chain where tokens are locked
DESIRED_AMOUNT="100000000"
DESIRED_CHAIN_ID=$CONNECTED_CHAIN_ID  # Connected chain where Alice wants tokens (2 for Move VM)
SOLVER_SIGNATURE=$(generate_solver_signature \
    "bob-chain1" \
    "$CHAIN1_ADDRESS" \
    "$OFFERED_FA_METADATA_CHAIN1" \
    "$OFFERED_AMOUNT" \
    "$OFFERED_CHAIN_ID" \
    "$DESIRED_FA_METADATA_CHAIN2" \
    "$DESIRED_AMOUNT" \
    "$DESIRED_CHAIN_ID" \
    "$EXPIRY_TIME" \
    "$ALICE_CHAIN1_ADDRESS" \
    "$BOB_CHAIN1_ADDRESS" \
    "1" \
    "$LOG_FILE")

if [ -z "$SOLVER_SIGNATURE" ]; then
    log_and_echo "     ❌ Failed to generate solver signature"
    exit 1
fi

log "     ✅ Solver signature generated: ${SOLVER_SIGNATURE:0:20}..."

# Extract public key from log file (sign_intent outputs it to stderr with "PUBLIC_KEY:" prefix)
SOLVER_PUBLIC_KEY=$(grep "PUBLIC_KEY:" "$LOG_FILE" | tail -1 | sed 's/.*PUBLIC_KEY://')
if [ -z "$SOLVER_PUBLIC_KEY" ]; then
    log_and_echo "     ❌ Failed to extract solver public key from sign_intent output"
    exit 1
fi
log "     ✅ Solver public key extracted: ${SOLVER_PUBLIC_KEY:0:20}..."

# Remove 0x prefix from signature and verifier public key for hex format
SOLVER_SIGNATURE_HEX="${SOLVER_SIGNATURE#0x}"
VERIFIER_PUBLIC_KEY_HEX="${VERIFIER_PUBLIC_KEY#0x}"
HUB_CHAIN_ID=1

# Call create_outflow_request_intent_entry
# Parameters: offered_metadata, offered_amount, offered_chain_id, desired_metadata, desired_amount,
#             desired_chain_id, expiry_time, intent_id, requester_address_connected_chain,
#             verifier_public_key, solver, solver_signature
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::create_outflow_request_intent_entry" \
    --args "address:${OFFERED_FA_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "address:${DESIRED_FA_METADATA_CHAIN2}" "u64:${DESIRED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${ALICE_CHAIN2_ADDRESS}" "hex:${VERIFIER_PUBLIC_KEY_HEX}" "address:${BOB_CHAIN1_ADDRESS}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Outflow request intent created on Chain 1!"

    # Verify request intent was stored on-chain by checking requester (Alice)'s latest transaction
    sleep 2
    log "     - Verifying request intent stored on-chain..."
    
    # Get the API response for debugging
    API_RESPONSE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" 2>&1)
    CURL_EXIT_CODE=$?
    
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        log_and_echo "     ❌ ERROR: Failed to fetch transactions from API"
        log_and_echo "     Curl exit code: $CURL_EXIT_CODE"
        log_and_echo "     Response: $API_RESPONSE"
        exit 1
    fi
    
    # Log the raw response structure for debugging
    log "     - API Response structure:"
    echo "$API_RESPONSE" | jq 'if type == "array" then "Array with \(length) items" else "Not an array: \(type)" end' 2>&1 | while IFS= read -r line; do
        log "       $line"
    done
    
    # Check if we have transactions
    TX_COUNT=$(echo "$API_RESPONSE" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
    log "     - Transaction count: $TX_COUNT"
    
    if [ "$TX_COUNT" = "0" ]; then
        log_and_echo "     ❌ ERROR: No transactions found in API response"
        log_and_echo "     Full API response saved to log file"
        echo "$API_RESPONSE" | jq '.' >> "$LOG_FILE" 2>&1 || echo "$API_RESPONSE" >> "$LOG_FILE"
        exit 1
    fi
    
    # Check events structure
    EVENTS_COUNT=$(echo "$API_RESPONSE" | jq -r '.[0].events // [] | if type == "array" then length else "not_array" end' 2>/dev/null || echo "error")
    log "     - Events count in first transaction: $EVENTS_COUNT"
    
    # Log all event types for debugging
    log "     - Event types found:"
    echo "$API_RESPONSE" | jq -r '.[0].events // [] | .[]? | if type == "object" and has("type") then .type else "no_type_field" end' 2>/dev/null | while IFS= read -r event_type; do
        log "       - $event_type"
    done
    
    # Try to extract intent address
    HUB_INTENT_ADDRESS=$(echo "$API_RESPONSE" | \
        jq -r '.[0].events // [] | .[]? | select(type == "object" and has("type") and (.type | type == "string") and ((.type | contains("LimitOrderEvent")) or (.type | contains("OracleLimitOrderEvent")))) | .data.intent_address? // empty' 2>&1 | head -n 1)
    
    JQ_EXIT_CODE=${PIPESTATUS[1]}
    
    if [ $JQ_EXIT_CODE -ne 0 ]; then
        log_and_echo "     ❌ ERROR: jq command failed with exit code $JQ_EXIT_CODE"
        log_and_echo "     jq output: $HUB_INTENT_ADDRESS"
        log_and_echo "     Full API response saved to log file for debugging"
        echo "$API_RESPONSE" | jq '.' >> "$LOG_FILE" 2>&1 || echo "$API_RESPONSE" >> "$LOG_FILE"
        exit 1
    fi

    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ] && [ "$HUB_INTENT_ADDRESS" != "empty" ]; then
        log "     ✅ Hub outflow request intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Outflow request intent created"
    else
        log_and_echo "     ❌ ERROR: Could not verify hub outflow request intent address"
        log_and_echo "     Extracted address: '$HUB_INTENT_ADDRESS'"
        log_and_echo "     Full API response saved to log file for debugging"
        echo "$API_RESPONSE" | jq '.' >> "$LOG_FILE" 2>&1 || echo "$API_RESPONSE" >> "$LOG_FILE"
        exit 1
    fi
else
    log_and_echo "     ❌ Outflow request intent creation failed on Chain 1!"
    log_and_echo "   Log file contents:"
    cat "$LOG_FILE"
    exit 1
fi

log ""
log "🎉 HUB CHAIN OUTFLOW INTENT CREATION COMPLETE!"
log "==============================================="
log ""
log "✅ Step completed successfully:"
log "   1. Outflow request intent created on Chain 1 (hub chain)"
log "   2. Tokens locked on hub chain"
log ""
log "📋 Request Intent Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Outflow Request Intent: $HUB_INTENT_ADDRESS"
fi
log "   Requester address on connected chain: $ALICE_CHAIN2_ADDRESS"

# Export values for use by other scripts
save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"

# Check final balances using common function
display_balances_hub
display_balances_connected_apt
log_and_echo ""

