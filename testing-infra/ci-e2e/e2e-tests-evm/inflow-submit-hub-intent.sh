#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root and logging
setup_project_root
setup_logging "inflow-submit-hub-intent-evm"
cd "$PROJECT_ROOT"

# Generate a random intent_id that will be used for both hub and escrow
INTENT_ID="0x$(openssl rand -hex 32)"

# EVM mode: CONNECTED_CHAIN_ID=31337
CONNECTED_CHAIN_ID=31337

# Get addresses
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1")

# Get Requester and Solver addresses
REQUESTER_CHAIN1_ADDRESS=$(get_profile_address "requester-chain1")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")

# Get USDxyz EVM address
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true
USDXYZ_EVM_ADDRESS="${USDXYZ_EVM_ADDRESS:-}"

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Requester Chain 1 (hub):     $REQUESTER_CHAIN1_ADDRESS"
log "   Solver Chain 1 (hub):       $SOLVER_CHAIN1_ADDRESS"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

# Generate solver signature using helper function
# For cross-chain intents: offered tokens are on connected chain, desired tokens are on hub chain (chain 1)
OFFERED_AMOUNT="1000000"  # 1 USDxyz = 1_000_000 (6 decimals, on EVM chain)
DESIRED_AMOUNT="1000000"  # 1 USDxyz = 1_000_000 (6 decimals, on hub chain)
OFFERED_CHAIN_ID=$CONNECTED_CHAIN_ID  # Connected chain where escrow will be created (31337 for EVM)
DESIRED_CHAIN_ID=1  # Hub chain where intent is created
HUB_CHAIN_ID=1
EVM_ADDRESS="0x0000000000000000000000000000000000000001"

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Offered amount: $OFFERED_AMOUNT (1 USDxyz)"
log "   Desired amount: $DESIRED_AMOUNT (1 USDxyz)"

# Check and display initial balances using common function
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_EVM_ADDRESS"
log_and_echo ""

# Get USDxyz metadata addresses
log ""
log "   - Getting USDxyz metadata addresses..."
log "     Getting USDxyz metadata on Chain 1 (hub)..."
USDXYZ_METADATA_CHAIN1=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN1" "1")
log "     ✅ Got USDxyz metadata on Chain 1: $USDXYZ_METADATA_CHAIN1"

# For EVM inflow: offered token is on EVM chain (connected), desired token is on hub
# Convert 20-byte Ethereum address to 32-byte Move address by padding with zeros
# Lowercase for consistent matching with solver acceptance config
EVM_TOKEN_ADDRESS_NO_PREFIX="${USDXYZ_EVM_ADDRESS#0x}"
EVM_TOKEN_ADDRESS_LOWER=$(echo "$EVM_TOKEN_ADDRESS_NO_PREFIX" | tr '[:upper:]' '[:lower:]')
OFFERED_METADATA_EVM="0x000000000000000000000000${EVM_TOKEN_ADDRESS_LOWER}"
DESIRED_METADATA_CHAIN1="$USDXYZ_METADATA_CHAIN1"
log "     EVM USDxyz token address: $USDXYZ_EVM_ADDRESS"
log "     Padded to 32-byte format: $OFFERED_METADATA_EVM"
log "     Inflow configuration:"
log "       Offered metadata (EVM connected chain): $OFFERED_METADATA_EVM"
log "       Desired metadata (hub chain 1): $DESIRED_METADATA_CHAIN1"

# ============================================================================
# SECTION 4: REGISTER SOLVER ON-CHAIN (prerequisite for signature validation)
# ============================================================================
log ""
log "   Registering solver on-chain (prerequisite for verifier validation)..."

# Get solver's public key by running sign_intent with a dummy call to extract key
log "   - Getting solver public key..."
SOLVER_PUBLIC_KEY_OUTPUT=$(cd "$PROJECT_ROOT" && env HOME="${HOME}" nix develop -c bash -c "cd solver && cargo run --bin sign_intent -- --profile solver-chain1 --chain-address $CHAIN1_ADDRESS --offered-metadata $OFFERED_METADATA_EVM --offered-amount $OFFERED_AMOUNT --offered-chain-id $OFFERED_CHAIN_ID --desired-metadata $DESIRED_METADATA_CHAIN1 --desired-amount $DESIRED_AMOUNT --desired-chain-id $DESIRED_CHAIN_ID --expiry-time $EXPIRY_TIME --issuer 0x$REQUESTER_CHAIN1_ADDRESS --solver 0x$SOLVER_CHAIN1_ADDRESS --chain-num 1 2>&1" | tee -a "$LOG_FILE")

SOLVER_PUBLIC_KEY=$(echo "$SOLVER_PUBLIC_KEY_OUTPUT" | grep "PUBLIC_KEY:" | tail -1 | sed 's/.*PUBLIC_KEY://')
if [ -z "$SOLVER_PUBLIC_KEY" ]; then
    log_and_echo "❌ Failed to extract solver public key"
    log_and_echo "Command output:"
    echo "$SOLVER_PUBLIC_KEY_OUTPUT"
    exit 1
fi
log "     ✅ Solver public key: ${SOLVER_PUBLIC_KEY:0:20}..."

log "   - Registering solver in solver registry..."
register_solver "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY" "$EVM_ADDRESS" "" "$LOG_FILE"

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
    "$OFFERED_METADATA_EVM" \
    "$OFFERED_AMOUNT" \
    "$OFFERED_CHAIN_ID" \
    "$DESIRED_METADATA_CHAIN1" \
    "$DESIRED_AMOUNT" \
    "$DESIRED_CHAIN_ID" \
    "$EXPIRY_TIME" \
    "$INTENT_ID" \
    "$REQUESTER_CHAIN1_ADDRESS" \
    "{\"chain_address\": \"$CHAIN1_ADDRESS\", \"flow_type\": \"inflow\", \"connected_chain_type\": \"evm\"}")

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
# SECTION 6: CREATE INTENT ON-CHAIN WITH RETRIEVED SIGNATURE
# ============================================================================
log ""
log "   Creating cross-chain intent on Chain 1..."
log "     Offered metadata: $OFFERED_METADATA_EVM"
log "     Desired metadata: $DESIRED_METADATA_CHAIN1"
log "     Solver address: $RETRIEVED_SOLVER"

SOLVER_SIGNATURE_HEX="${RETRIEVED_SIGNATURE#0x}"
aptos move run --profile requester-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_inflow::create_inflow_intent_entry" \
    --args "address:${OFFERED_METADATA_EVM}" "u64:${OFFERED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "address:${DESIRED_METADATA_CHAIN1}" "u64:${DESIRED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${RETRIEVED_SOLVER}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 7: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Intent created on Chain 1!"
    
    # Verify intent was stored on-chain by checking Requester's latest transaction
    sleep 2
    log "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${REQUESTER_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent")) | .data.intent_address' | head -n 1)
    
    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Intent created (via verifier negotiation)"
    else
        log_and_echo "     ❌ ERROR: Could not verify hub intent address"
        exit 1
    fi
else
    log_and_echo "     ❌ Intent creation failed on Chain 1!"
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
log "🎉 HUB CHAIN INTENT CREATION COMPLETE!"
log "======================================="
log ""
log "✅ Steps completed successfully (via verifier-based negotiation):"
log "   1. Solver registered on-chain"
log "   2. Requester submitted draft intent to verifier"
log "   3. Solver service signed draft automatically (FCFS)"
log "   4. Requester polled verifier and retrieved signature"
log "   5. Requester created intent on-chain with retrieved signature"
log ""
log "📋 Intent Details:"
log "   Intent ID: $INTENT_ID"
log "   Draft ID: $DRAFT_ID"
log "   Solver: $RETRIEVED_SOLVER"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Intent: $HUB_INTENT_ADDRESS"
fi

# Export values for use by other scripts
save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"

# Check final balances using common function
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_EVM_ADDRESS"
log_and_echo ""

