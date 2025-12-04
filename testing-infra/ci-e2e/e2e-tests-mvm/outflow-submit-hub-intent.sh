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
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1")
TEST_TOKENS_CHAIN2=$(get_profile_address "test-tokens-chain2")
REQUESTER_CHAIN1_ADDRESS=$(get_profile_address "requester-chain1")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")
REQUESTER_CHAIN2_ADDRESS=$(get_profile_address "requester-chain2")
SOLVER_CHAIN2_ADDRESS=$(get_profile_address "solver-chain2")

log ""
log "📋 Chain Information:"
log "   Hub Chain Module Address (Chain 1):     $CHAIN1_ADDRESS"
log "   Connected Chain Module Address (Chain 2): $CHAIN2_ADDRESS"
log "   Requester Chain 1 (hub):     $REQUESTER_CHAIN1_ADDRESS"
log "   Solver Chain 1 (hub):       $SOLVER_CHAIN1_ADDRESS"
log "   Requester Chain 2 (connected): $REQUESTER_CHAIN2_ADDRESS"
log "   Solver Chain 2 (connected): $SOLVER_CHAIN2_ADDRESS"

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
# USDxyz amounts: 1 USDxyz (6 decimals = 1_000_000)
OFFERED_AMOUNT="1000000"  # 1 USDxyz = 1_000_000
DESIRED_AMOUNT="1000000"  # 1 USDxyz = 1_000_000
OFFERED_CHAIN_ID=1
DESIRED_CHAIN_ID=$CONNECTED_CHAIN_ID
HUB_CHAIN_ID=1
EVM_ADDRESS="0x0000000000000000000000000000000000000001"

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Verifier public key: $VERIFIER_PUBLIC_KEY"
log "   Offered amount: $OFFERED_AMOUNT (1 USDxyz)"
log "   Desired amount: $DESIRED_AMOUNT (1 USDxyz)"

# Get test tokens addresses from profiles
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1")
TEST_TOKENS_CHAIN2=$(get_profile_address "test-tokens-chain2")

log ""
log "   - Getting USDxyz metadata addresses..."
log "     Getting USDxyz metadata on Chain 1..."
USDXYZ_METADATA_CHAIN1=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN1" "1")
log "     ✅ Got USDxyz metadata on Chain 1: $USDXYZ_METADATA_CHAIN1"
OFFERED_METADATA_CHAIN1="$USDXYZ_METADATA_CHAIN1"

log "     Getting USDxyz metadata on Chain 2..."
USDXYZ_METADATA_CHAIN2=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN2" "2")
log "     ✅ Got USDxyz metadata on Chain 2: $USDXYZ_METADATA_CHAIN2"
DESIRED_METADATA_CHAIN2="$USDXYZ_METADATA_CHAIN2"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_mvm "0x$TEST_TOKENS_CHAIN2"
log_and_echo ""

# ============================================================================
# SECTION 4: REGISTER SOLVER ON-CHAIN (prerequisite for signature validation)
# ============================================================================
log ""
log "   Registering solver on-chain (prerequisite for verifier validation)..."

# Get solver's public key by running sign_intent with a dummy call to extract key
log "   - Getting solver public key..."
SOLVER_PUBLIC_KEY_OUTPUT=$(cd "$PROJECT_ROOT" && env HOME="${HOME}" nix develop -c bash -c "cd solver && cargo run --bin sign_intent -- --profile solver-chain1 --chain-address $CHAIN1_ADDRESS --offered-metadata $OFFERED_METADATA_CHAIN1 --offered-amount $OFFERED_AMOUNT --offered-chain-id $OFFERED_CHAIN_ID --desired-metadata $DESIRED_METADATA_CHAIN2 --desired-amount $DESIRED_AMOUNT --desired-chain-id $DESIRED_CHAIN_ID --expiry-time $EXPIRY_TIME --issuer 0x$REQUESTER_CHAIN1_ADDRESS --solver 0x$SOLVER_CHAIN1_ADDRESS --chain-num 1 2>&1" | tee -a "$LOG_FILE")

SOLVER_PUBLIC_KEY=$(echo "$SOLVER_PUBLIC_KEY_OUTPUT" | grep "PUBLIC_KEY:" | tail -1 | sed 's/.*PUBLIC_KEY://')
if [ -z "$SOLVER_PUBLIC_KEY" ]; then
    log_and_echo "❌ Failed to extract solver public key"
    log_and_echo "Command output:"
    echo "$SOLVER_PUBLIC_KEY_OUTPUT"
    exit 1
fi
log "     ✅ Solver public key: ${SOLVER_PUBLIC_KEY:0:20}..."

log "   - Registering solver in solver registry..."
register_solver "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY" "$EVM_ADDRESS" "$SOLVER_CHAIN2_ADDRESS" "$LOG_FILE"

log "   - Waiting for solver registration to be confirmed on-chain (5 seconds)..."
sleep 5

log "   - Verifying solver registration..."
verify_solver_registered "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_CHAIN1_ADDRESS" "$LOG_FILE"

# ============================================================================
# SECTION 5: VERIFIER-BASED NEGOTIATION ROUTING
# ============================================================================
log ""
log "🔄 Starting verifier-based negotiation routing..."
log "   Flow: Requester → Verifier → Solver → Verifier → Requester"

# Step 1: Requester submits draft intent to verifier
log ""
log "   Step 1: Requester submits draft intent to verifier..."
DRAFT_DATA=$(build_draft_data \
    "$OFFERED_METADATA_CHAIN1" \
    "$OFFERED_AMOUNT" \
    "$OFFERED_CHAIN_ID" \
    "$DESIRED_METADATA_CHAIN2" \
    "$DESIRED_AMOUNT" \
    "$DESIRED_CHAIN_ID" \
    "$EXPIRY_TIME" \
    "$INTENT_ID" \
    "$REQUESTER_CHAIN1_ADDRESS" \
    "{\"chain_address\": \"$CHAIN1_ADDRESS\", \"flow_type\": \"outflow\", \"requester_connected_chain_address\": \"$REQUESTER_CHAIN2_ADDRESS\"}")

DRAFT_ID=$(submit_draft_intent "$REQUESTER_CHAIN1_ADDRESS" "$DRAFT_DATA" "$EXPIRY_TIME")
log "     Draft ID: $DRAFT_ID"

# Step 2: Wait for solver service to sign the draft (polls automatically)
# The solver service running in the background will:
# - Poll for pending drafts
# - Evaluate acceptance criteria
# - Generate signature
# - Submit signature to verifier (FCFS)
log ""
log "   Step 2: Waiting for solver service to sign draft..."
log "     (Solver service polls verifier automatically)"

# Poll for signature with retry logic (solver service needs time to process)
SIGNATURE_DATA=$(poll_for_signature "$DRAFT_ID" 10 2)
RETRIEVED_SIGNATURE=$(echo "$SIGNATURE_DATA" | jq -r '.signature')
RETRIEVED_SOLVER=$(echo "$SIGNATURE_DATA" | jq -r '.solver_address')

if [ -z "$RETRIEVED_SIGNATURE" ] || [ "$RETRIEVED_SIGNATURE" = "null" ]; then
    log_and_echo "❌ ERROR: Failed to retrieve signature from verifier"
    exit 1
fi
log "     ✅ Retrieved signature from solver: $RETRIEVED_SOLVER"
log "     Signature: ${RETRIEVED_SIGNATURE:0:20}..."

# ============================================================================
# SECTION 6: CREATE OUTFLOW INTENT ON-CHAIN WITH RETRIEVED SIGNATURE
# ============================================================================
log ""
log "   Creating outflow intent on hub chain..."
log "   - Requester locks 1 USDxyz on hub chain"
log "   - Requester wants 1 USDxyz on connected chain (Chain 2)"
log "     Offered metadata (hub): $OFFERED_METADATA_CHAIN1"
log "     Desired metadata (connected): $DESIRED_METADATA_CHAIN2"
log "     Solver address: $RETRIEVED_SOLVER"
log "     Requester address on connected chain: $REQUESTER_CHAIN2_ADDRESS"

SOLVER_SIGNATURE_HEX="${RETRIEVED_SIGNATURE#0x}"
VERIFIER_PUBLIC_KEY_HEX_CLEAN="${VERIFIER_PUBLIC_KEY#0x}"

aptos move run --profile requester-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::create_outflow_intent_entry" \
    --args "address:${OFFERED_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "address:${DESIRED_METADATA_CHAIN2}" "u64:${DESIRED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${REQUESTER_CHAIN2_ADDRESS}" "hex:${VERIFIER_PUBLIC_KEY_HEX_CLEAN}" "address:${RETRIEVED_SOLVER}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 7: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Outflow intent created on Chain 1!"

    sleep 2
    log "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${REQUESTER_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_address' | head -n 1)

    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub outflow intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Outflow intent created (via verifier negotiation)"
    else
        log_and_echo "❌ ERROR: Could not verify hub outflow intent address"
        exit 1
    fi
else
    log_and_echo "❌ Outflow intent creation failed on Chain 1!"
    log_and_echo "   Log file contents:"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    cat "$LOG_FILE"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
fi

# ============================================================================
# SECTION 8: FINAL SUMMARY
# ============================================================================
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_mvm "0x$TEST_TOKENS_CHAIN2"
log_and_echo ""

log ""
log "🎉 OUTFLOW - HUB CHAIN INTENT CREATION COMPLETE!"
log "================================================"
log ""
log "✅ Steps completed successfully (via verifier-based negotiation):"
log "   1. Solver registered on-chain"
log "   2. Requester submitted draft intent to verifier"
log "   3. Solver service signed draft automatically (FCFS)"
log "   4. Requester polled verifier and retrieved signature"
log "   5. Requester created outflow intent on-chain with retrieved signature"
log "   6. Tokens locked on hub chain"
log ""
log "📋 Request-intent Details:"
log "   Intent ID: $INTENT_ID"
log "   Draft ID: $DRAFT_ID"
log "   Solver: $RETRIEVED_SOLVER"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Outflow Request-intent: $HUB_INTENT_ADDRESS"
fi
log "   Requester address on connected chain: $REQUESTER_CHAIN2_ADDRESS"

save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"
