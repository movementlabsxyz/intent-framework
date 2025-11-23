#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-outflow-hub-intent"
cd "$PROJECT_ROOT"

# ============================================================================
# SECTION 1: LOAD DEPENDENCIES
# ============================================================================
# Generate a random intent_id for the outflow intent
INTENT_ID="0x$(openssl rand -hex 32)"

# ============================================================================
# SECTION 2: GET ADDRESSES AND CONFIGURATION
# ============================================================================
CONNECTED_CHAIN_ID=2
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
CHAIN2_ADDRESS=$(get_profile_address "intent-account-chain2")
ALICE_CHAIN1_ADDRESS=$(get_profile_address "alice-chain1")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")
ALICE_CHAIN2_ADDRESS=$(get_profile_address "alice-chain2")
BOB_CHAIN2_ADDRESS=$(get_profile_address "bob-chain2")

log ""
log "📋 Chain Information:"
log "   Hub Chain Module Address (Chain 1):     $CHAIN1_ADDRESS"
log "   Connected Chain Module Address (Chain 2): $CHAIN2_ADDRESS"
log "   Alice Chain 1 (hub):     $ALICE_CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Alice Chain 2 (connected): $ALICE_CHAIN2_ADDRESS"
log "   Bob Chain 2 (connected): $BOB_CHAIN2_ADDRESS"

VERIFIER_TESTING_CONFIG="${PROJECT_ROOT}/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

VERIFIER_PUBLIC_KEY_B64=$(grep "^public_key" "$VERIFIER_TESTING_CONFIG" | cut -d'"' -f2)

if [ -z "$VERIFIER_PUBLIC_KEY_B64" ]; then
    log_and_echo "❌ ERROR: Could not find public_key in verifier_testing.toml"
    log_and_echo "   The verifier public key is required for outflow intent creation."
    log_and_echo "   Please ensure verifier_testing.toml has a valid public_key field."
    exit 1
fi

VERIFIER_PUBLIC_KEY_HEX=$(echo "$VERIFIER_PUBLIC_KEY_B64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')

if [ -z "$VERIFIER_PUBLIC_KEY_HEX" ] || [ ${#VERIFIER_PUBLIC_KEY_HEX} -ne 64 ]; then
    log_and_echo "❌ ERROR: Invalid public key format in verifier_testing.toml"
    log_and_echo "   Expected: base64-encoded 32-byte Ed25519 public key"
    log_and_echo "   Got: $VERIFIER_PUBLIC_KEY_B64"
    log_and_echo "   Please ensure the public_key in verifier_testing.toml is valid base64 and decodes to 32 bytes (64 hex chars)."
    exit 1
fi

VERIFIER_PUBLIC_KEY="0x${VERIFIER_PUBLIC_KEY_HEX}"
EXPIRY_TIME=$(date -d "+1 hour" +%s)
# Bob gets funded with 200000000 Octas (2 APT), so half is 100000000 Octas (1 APT)
OFFERED_AMOUNT="100000000"  # 1 APT (half of Bob's 200000000 Octas)
DESIRED_AMOUNT="100000000"  # 1 APT (half of Bob's 200000000 Octas)
OFFERED_CHAIN_ID=1
DESIRED_CHAIN_ID=$CONNECTED_CHAIN_ID
HUB_CHAIN_ID=1

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Verifier public key: $VERIFIER_PUBLIC_KEY"
log "   Offered amount: $OFFERED_AMOUNT Octas (1 APT)"
log "   Desired amount: $DESIRED_AMOUNT Octas (1 APT)"

log ""
log "   - Getting APT metadata addresses..."
log "     Getting APT metadata on Chain 1..."
APT_METADATA_CHAIN1=$(extract_apt_metadata "alice-chain1" "$CHAIN1_ADDRESS" "$ALICE_CHAIN1_ADDRESS" "1" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 1: $APT_METADATA_CHAIN1"
OFFERED_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"

log "     Getting APT metadata on Chain 2..."
APT_METADATA_CHAIN2=$(extract_apt_metadata "alice-chain2" "$CHAIN2_ADDRESS" "$ALICE_CHAIN2_ADDRESS" "2" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 2: $APT_METADATA_CHAIN2"
DESIRED_FA_METADATA_CHAIN2="$APT_METADATA_CHAIN2"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_hub
display_balances_connected_mvm
log_and_echo ""

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Creating outflow request intent on hub chain..."
log "   - Requester (Alice) creates outflow request intent on Chain 1 (hub chain)"
log "   - Requester (Alice) locks 1 APT on hub chain"
log "   - Requester (Alice) wants 1 APT on connected chain (Chain 2)"
log "   - Using intent_id: $INTENT_ID"

log "   - Generating solver signature..."
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
    log_and_echo "❌ Failed to generate solver signature"
    exit 1
fi

log "     ✅ Solver signature generated: ${SOLVER_SIGNATURE:0:20}..."

SOLVER_PUBLIC_KEY=$(grep "PUBLIC_KEY:" "$LOG_FILE" | tail -1 | sed 's/.*PUBLIC_KEY://')
if [ -z "$SOLVER_PUBLIC_KEY" ]; then
    log_and_echo "❌ Failed to extract solver public key from sign_intent output"
    exit 1
fi
log "     ✅ Solver public key extracted: ${SOLVER_PUBLIC_KEY:0:20}..."

# EVM address placeholder (not used for MVM-only tests, but required for solver registration)
EVM_ADDRESS="0x0000000000000000000000000000000000000001"

log "   - Registering solver (Bob) in solver registry..."
# Register with EVM address and connected chain MVM address (Bob's Chain 2 address)
register_solver "bob-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY" "$EVM_ADDRESS" "$BOB_CHAIN2_ADDRESS" "$LOG_FILE"

log "   - Waiting for solver registration to be confirmed on-chain (5 seconds)..."
sleep 5

log "   - Verifying solver registration..."
verify_solver_registered "bob-chain1" "$CHAIN1_ADDRESS" "$BOB_CHAIN1_ADDRESS" "$LOG_FILE"

log "   - Creating outflow request intent on Chain 1..."
log "     Offered FA metadata (hub): $OFFERED_FA_METADATA_CHAIN1"
log "     Desired FA metadata (connected): $DESIRED_FA_METADATA_CHAIN2"
log "     Solver (Bob) address: $BOB_CHAIN1_ADDRESS"
log "     Requester address on connected chain: $ALICE_CHAIN2_ADDRESS"

SOLVER_SIGNATURE_HEX="${SOLVER_SIGNATURE#0x}"
VERIFIER_PUBLIC_KEY_HEX="${VERIFIER_PUBLIC_KEY#0x}"

aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::create_outflow_request_intent_entry" \
    --args "address:${OFFERED_FA_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "address:${DESIRED_FA_METADATA_CHAIN2}" "u64:${DESIRED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${ALICE_CHAIN2_ADDRESS}" "hex:${VERIFIER_PUBLIC_KEY_HEX}" "address:${BOB_CHAIN1_ADDRESS}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Outflow request intent created on Chain 1!"

    sleep 2
    log "     - Verifying request intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_address' | head -n 1)

    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub outflow request intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Outflow request intent created"
    else
        log_and_echo "❌ ERROR: Could not verify hub outflow request intent address"
        exit 1
    fi
else
    log_and_echo "❌ Outflow request intent creation failed on Chain 1!"
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
display_balances_hub
display_balances_connected_mvm
log_and_echo ""

log ""
log "🎉 OUTFLOW - HUB CHAIN INTENT CREATION COMPLETE!"
log "================================================"
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

save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"
