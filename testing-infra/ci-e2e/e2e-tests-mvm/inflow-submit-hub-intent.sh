#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-hub-intent"
cd "$PROJECT_ROOT"

# ============================================================================
# SECTION 1: LOAD DEPENDENCIES
# ============================================================================
# Generate a random intent_id that will be used for both hub and escrow
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

EXPIRY_TIME=$(date -d "+1 hour" +%s)
# Requester and Solver get funded with 1 USDxyz each, transfer 1 USDxyz
OFFERED_AMOUNT="100000000"  # 1 USDxyz (8 decimals = 100_000_000)
DESIRED_AMOUNT="100000000"  # 1 USDxyz (8 decimals = 100_000_000)
OFFERED_CHAIN_ID=$CONNECTED_CHAIN_ID
DESIRED_CHAIN_ID=1
HUB_CHAIN_ID=1
EVM_ADDRESS="0x0000000000000000000000000000000000000001"

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Offered amount: $OFFERED_AMOUNT (1 USDxyz)"
log "   Desired amount: $DESIRED_AMOUNT (1 USDxyz)"

log ""
log "   - Getting USDxyz metadata addresses..."
log "     Getting USDxyz metadata on Chain 1..."
USDXYZ_METADATA_CHAIN1=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN1" "1")
if [ -z "$USDXYZ_METADATA_CHAIN1" ]; then
    log_and_echo "❌ Failed to get USDxyz metadata on Chain 1"
    exit 1
fi
log "     ✅ Got USDxyz metadata on Chain 1: $USDXYZ_METADATA_CHAIN1"
OFFERED_METADATA_CHAIN1="$USDXYZ_METADATA_CHAIN1"
DESIRED_METADATA_CHAIN1="$USDXYZ_METADATA_CHAIN1"

log "     Getting USDxyz metadata on Chain 2..."
USDXYZ_METADATA_CHAIN2=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN2" "2")
if [ -z "$USDXYZ_METADATA_CHAIN2" ]; then
    log_and_echo "❌ Failed to get USDxyz metadata on Chain 2"
    exit 1
fi
log "     ✅ Got USDxyz metadata on Chain 2: $USDXYZ_METADATA_CHAIN2"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
# Check and display initial balances using common function
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
SOLVER_PUBLIC_KEY_OUTPUT=$(cd "$PROJECT_ROOT" && env HOME="${HOME}" nix develop -c bash -c "cd solver && cargo run --bin sign_intent -- --profile solver-chain1 --chain-address $CHAIN1_ADDRESS --offered-metadata $OFFERED_METADATA_CHAIN1 --offered-amount $OFFERED_AMOUNT --offered-chain-id $OFFERED_CHAIN_ID --desired-metadata $DESIRED_METADATA_CHAIN1 --desired-amount $DESIRED_AMOUNT --desired-chain-id $DESIRED_CHAIN_ID --expiry-time $EXPIRY_TIME --issuer $REQUESTER_CHAIN1_ADDRESS --solver $SOLVER_CHAIN1_ADDRESS --chain-num 1 2>&1" | tee -a "$LOG_FILE")

SOLVER_PUBLIC_KEY=$(echo "$SOLVER_PUBLIC_KEY_OUTPUT" | grep "PUBLIC_KEY:" | tail -1 | sed 's/.*PUBLIC_KEY://')
if [ -z "$SOLVER_PUBLIC_KEY" ]; then
    log_and_echo "❌ Failed to extract solver public key"
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
    "$DESIRED_METADATA_CHAIN1" \
    "$DESIRED_AMOUNT" \
    "$DESIRED_CHAIN_ID" \
    "$EXPIRY_TIME" \
    "$INTENT_ID" \
    "$REQUESTER_CHAIN1_ADDRESS" \
    "{\"chain_address\": \"$CHAIN1_ADDRESS\", \"flow_type\": \"inflow\"}")

DRAFT_ID=$(submit_draft_intent "$REQUESTER_CHAIN1_ADDRESS" "$DRAFT_DATA" "$EXPIRY_TIME")
log "     Draft ID: $DRAFT_ID"

# Step 2: Solver polls verifier for pending drafts (simulated - in real scenario solver runs separately)
log ""
log "   Step 2: Solver polls verifier for pending drafts..."
PENDING_DRAFTS=$(poll_pending_drafts)
DRAFT_COUNT=$(echo "$PENDING_DRAFTS" | jq 'length')
log "     Found $DRAFT_COUNT pending draft(s)"

# Find our draft
OUR_DRAFT=$(echo "$PENDING_DRAFTS" | jq -r ".[] | select(.draft_id == \"$DRAFT_ID\")")
if [ -z "$OUR_DRAFT" ] || [ "$OUR_DRAFT" = "null" ]; then
    log_and_echo "❌ ERROR: Our draft not found in pending drafts"
    exit 1
fi
log "     ✅ Found our draft in pending list"

# Step 3: Solver generates signature for the draft
log ""
log "   Step 3: Solver generates signature for draft..."
SOLVER_SIGNATURE=$(generate_solver_signature \
    "solver-chain1" \
    "$CHAIN1_ADDRESS" \
    "$OFFERED_METADATA_CHAIN1" \
    "$OFFERED_AMOUNT" \
    "$OFFERED_CHAIN_ID" \
    "$DESIRED_METADATA_CHAIN1" \
    "$DESIRED_AMOUNT" \
    "$DESIRED_CHAIN_ID" \
    "$EXPIRY_TIME" \
    "$REQUESTER_CHAIN1_ADDRESS" \
    "$SOLVER_CHAIN1_ADDRESS" \
    "1" \
    "$LOG_FILE")

if [ -z "$SOLVER_SIGNATURE" ] || [[ ! "$SOLVER_SIGNATURE" =~ ^0x[0-9a-fA-F]+$ ]]; then
    log_and_echo "❌ Failed to generate solver signature"
    log_and_echo "   Output was: $SOLVER_SIGNATURE"
    exit 1
fi
log "     ✅ Solver signature generated: ${SOLVER_SIGNATURE:0:20}..."

# Step 4: Solver submits signature to verifier
log ""
log "   Step 4: Solver submits signature to verifier (FCFS)..."
submit_signature_to_verifier "$DRAFT_ID" "$SOLVER_CHAIN1_ADDRESS" "$SOLVER_SIGNATURE" "$SOLVER_PUBLIC_KEY"

# Step 5: Requester polls verifier for signature
log ""
log "   Step 5: Requester polls verifier for signature..."
SIGNATURE_DATA=$(poll_for_signature "$DRAFT_ID" 3 2)
RETRIEVED_SIGNATURE=$(echo "$SIGNATURE_DATA" | jq -r '.signature')
RETRIEVED_SOLVER=$(echo "$SIGNATURE_DATA" | jq -r '.solver_address')

if [ -z "$RETRIEVED_SIGNATURE" ] || [ "$RETRIEVED_SIGNATURE" = "null" ]; then
    log_and_echo "❌ ERROR: Failed to retrieve signature from verifier"
    exit 1
fi
log "     ✅ Retrieved signature from solver: $RETRIEVED_SOLVER"
log "     Signature: ${RETRIEVED_SIGNATURE:0:20}..."

# ============================================================================
# SECTION 6: CREATE INTENT ON-CHAIN WITH RETRIEVED SIGNATURE
# ============================================================================
log ""
log "   Creating cross-chain request-intent on Chain 1..."
log "     Offered metadata: $OFFERED_METADATA_CHAIN1"
log "     Desired metadata: $DESIRED_METADATA_CHAIN1"
log "     Solver address: $RETRIEVED_SOLVER"

SOLVER_SIGNATURE_HEX="${RETRIEVED_SIGNATURE#0x}"
aptos move run --profile requester-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_inflow::create_inflow_request_intent_entry" \
    --args "address:${OFFERED_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "address:${DESIRED_METADATA_CHAIN1}" "u64:${DESIRED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${RETRIEVED_SOLVER}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 7: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Request-intent created on Chain 1!"

    sleep 2
    log "     - Verifying request-intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${REQUESTER_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent")) | .data.intent_address' | head -n 1)

    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub request-intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Request-intent created (via verifier negotiation)"
    else
        log_and_echo "❌ ERROR: Could not verify hub request-intent address"
        exit 1
    fi
else
    log_and_echo "❌ Request-intent creation failed on Chain 1!"
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
log "🎉 INFLOW - HUB CHAIN INTENT CREATION COMPLETE!"
log "================================================"
log ""
log "✅ Steps completed successfully (via verifier-based negotiation):"
log "   1. Solver registered on-chain"
log "   2. Requester submitted draft intent to verifier"
log "   3. Solver polled verifier and found pending draft"
log "   4. Solver signed draft and submitted signature to verifier (FCFS)"
log "   5. Requester polled verifier and retrieved signature"
log "   6. Requester created intent on-chain with retrieved signature"
log ""
log "📋 Request-intent Details:"
log "   Intent ID: $INTENT_ID"
log "   Draft ID: $DRAFT_ID"
log "   Solver: $RETRIEVED_SOLVER"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Request-intent: $HUB_INTENT_ADDRESS"
fi

save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"


