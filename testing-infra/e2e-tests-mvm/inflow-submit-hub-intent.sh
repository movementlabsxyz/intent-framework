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
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Creating request-intent on hub chain..."
log "   - Requester (Requester) creates request-intent on Chain 1 (hub chain)"
log "   - Request-intent requests 1 USDxyz to be provided by solver (Solver)"
log "   - Using intent_id: $INTENT_ID"

log "   - Generating solver signature..."
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

SOLVER_PUBLIC_KEY=$(grep "PUBLIC_KEY:" "$LOG_FILE" | tail -1 | sed 's/.*PUBLIC_KEY://')
if [ -z "$SOLVER_PUBLIC_KEY" ]; then
    log_and_echo "❌ Failed to extract solver public key from sign_intent output"
    exit 1
fi
log "     ✅ Solver public key extracted: ${SOLVER_PUBLIC_KEY:0:20}..."

log "   - Registering solver (Solver) in solver registry..."
# Register with EVM address and connected chain MVM address (Solver's Chain 2 address) for consistency
register_solver "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY" "$EVM_ADDRESS" "$SOLVER_CHAIN2_ADDRESS" "$LOG_FILE"

log "   - Waiting for solver registration to be confirmed on-chain (5 seconds)..."
sleep 5

log "   - Verifying solver registration..."
verify_solver_registered "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_CHAIN1_ADDRESS" "$LOG_FILE"

log "   - Creating cross-chain request-intent on Chain 1..."
log "     Offered metadata: $OFFERED_METADATA_CHAIN1"
log "     Desired metadata: $DESIRED_METADATA_CHAIN1"
log "     Solver (Solver) address: $SOLVER_CHAIN1_ADDRESS"

SOLVER_SIGNATURE_HEX="${SOLVER_SIGNATURE#0x}"
aptos move run --profile requester-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_inflow::create_inflow_request_intent_entry" \
    --args "address:${OFFERED_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "address:${DESIRED_METADATA_CHAIN1}" "u64:${DESIRED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${SOLVER_CHAIN1_ADDRESS}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Request-intent created on Chain 1!"

    sleep 2
    log "     - Verifying request-intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${REQUESTER_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent")) | .data.intent_address' | head -n 1)

    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub request-intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Request-intent created"
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
# SECTION 6: FINAL SUMMARY
# ============================================================================
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_mvm "0x$TEST_TOKENS_CHAIN2"
log_and_echo ""

log ""
log "🎉 INFLOW - HUB CHAIN INTENT CREATION COMPLETE!"
log "================================================"
log ""
log "✅ Step completed successfully:"
log "   1. Request-intent created on Chain 1 (hub chain)"
log ""
log "📋 Request-intent Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Request-intent: $HUB_INTENT_ADDRESS"
fi

save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"


