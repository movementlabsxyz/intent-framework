#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-outflow-solver-transfer"
cd "$PROJECT_ROOT"

# ============================================================================
# SECTION 1: LOAD DEPENDENCIES
# ============================================================================
if ! load_intent_info "INTENT_ID"; then
    exit 1
fi

# ============================================================================
# SECTION 2: GET ADDRESSES AND CONFIGURATION
# ============================================================================
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
CHAIN2_ADDRESS=$(get_profile_address "intent-account-chain2")
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

TRANSFER_AMOUNT="1000000"  # 1 USDxyz (6 decimals = 1_000_000)

# Get test tokens address
TEST_TOKENS_CHAIN2=$(get_profile_address "test-tokens-chain2")

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Transfer Amount: $TRANSFER_AMOUNT (1 USDxyz)"

log ""
log "   - Getting USDxyz metadata on Chain 2..."
USDXYZ_METADATA_CHAIN2=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN2" "2")
log "     ✅ Got USDxyz metadata on Chain 2: $USDXYZ_METADATA_CHAIN2"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_connected_mvm "0x$TEST_TOKENS_CHAIN2"
log_and_echo ""

REQUESTER_CHAIN2_USDXYZ_INIT=$(get_usdxyz_balance "requester-chain2" "2" "0x$TEST_TOKENS_CHAIN2")
SOLVER_CHAIN2_USDXYZ_INIT=$(get_usdxyz_balance "solver-chain2" "2" "0x$TEST_TOKENS_CHAIN2")

log "   Requester Chain 2 initial USDxyz balance: $REQUESTER_CHAIN2_USDXYZ_INIT USDxyz.10e8"
log "   Solver Chain 2 initial USDxyz balance: $SOLVER_CHAIN2_USDXYZ_INIT USDxyz.10e8"

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Executing solver transfer on connected chain..."
log "   - Solver (Solver) transfers USDxyz directly to requester (Requester) on Chain 2"
log "   - This is a DIRECT TRANSFER, not an escrow"
log "   - Requester (Requester) receives USDxyz immediately on Chain 2"
log "   - Amount: $TRANSFER_AMOUNT (1 USDxyz)"
log "   - Intent ID included in transaction for verifier tracking"

aptos move run --profile solver-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::utils::transfer_with_intent_id" \
    --args "address:${REQUESTER_CHAIN2_ADDRESS}" "address:${USDXYZ_METADATA_CHAIN2}" "u64:${TRANSFER_AMOUNT}" "address:${INTENT_ID}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Solver transfer completed on Chain 2!"

    sleep 2

    log "     - Extracting transaction hash..."
    TX_HASH=$(curl -s "http://127.0.0.1:8082/v1/accounts/${SOLVER_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].hash' | head -n 1)

    if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
        log_and_echo "❌ ERROR: Could not extract transaction hash"
        exit 1
    fi

    log "     ✅ Transaction hash: $TX_HASH"

    log "     - Verifying transfer by checking USDxyz balances..."
    REQUESTER_CHAIN2_USDXYZ_FINAL=$(get_usdxyz_balance "requester-chain2" "2" "0x$TEST_TOKENS_CHAIN2")
    SOLVER_CHAIN2_USDXYZ_FINAL=$(get_usdxyz_balance "solver-chain2" "2" "0x$TEST_TOKENS_CHAIN2")

    log "     Requester Chain 2 final USDxyz balance: $REQUESTER_CHAIN2_USDXYZ_FINAL USDxyz.10e8"
    log "     Solver Chain 2 final USDxyz balance: $SOLVER_CHAIN2_USDXYZ_FINAL USDxyz.10e8"

    REQUESTER_CHAIN2_USDXYZ_EXPECTED=$((REQUESTER_CHAIN2_USDXYZ_INIT + TRANSFER_AMOUNT))

    if [ "$REQUESTER_CHAIN2_USDXYZ_FINAL" -eq "$REQUESTER_CHAIN2_USDXYZ_EXPECTED" ]; then
        log "     ✅ Requester (Requester) Chain 2 USDxyz balance increased by $TRANSFER_AMOUNT as expected"
    else
        log_and_echo "❌ ERROR: Requester (Requester) Chain 2 USDxyz balance mismatch"
        log_and_echo "   Expected: $REQUESTER_CHAIN2_USDXYZ_EXPECTED USDxyz.10e8"
        log_and_echo "   Got: $REQUESTER_CHAIN2_USDXYZ_FINAL USDxyz.10e8"
        exit 1
    fi

    SOLVER_CHAIN2_USDXYZ_DECREASE=$((SOLVER_CHAIN2_USDXYZ_INIT - SOLVER_CHAIN2_USDXYZ_FINAL))
    if [ "$SOLVER_CHAIN2_USDXYZ_DECREASE" -eq "$TRANSFER_AMOUNT" ]; then
        log "     ✅ Solver (Solver) Chain 2 USDxyz balance decreased by $SOLVER_CHAIN2_USDXYZ_DECREASE USDxyz.10e8 as expected"
    else
        log_and_echo "❌ ERROR: Solver (Solver) Chain 2 USDxyz balance did not decrease as expected"
        log_and_echo "   Initial: $SOLVER_CHAIN2_USDXYZ_INIT USDxyz.10e8"
        log_and_echo "   Final: $SOLVER_CHAIN2_USDXYZ_FINAL USDxyz.10e8"
        exit 1
    fi

    TRANSFER_INFO_FILE="${PROJECT_ROOT}/.tmp/outflow-transfer-info.txt"
    mkdir -p "${PROJECT_ROOT}/.tmp"
    echo "CONNECTED_CHAIN_TX_HASH=$TX_HASH" > "$TRANSFER_INFO_FILE"
    echo "INTENT_ID=$INTENT_ID" >> "$TRANSFER_INFO_FILE"
    log "     ✅ Transaction info saved to $TRANSFER_INFO_FILE"

    log_and_echo "✅ Solver transfer completed"
else
    log_and_echo "❌ Solver transfer failed on Chain 2!"
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
display_balances_connected_mvm "0x$TEST_TOKENS_CHAIN2"
log_and_echo ""

log ""
log "🎉 OUTFLOW - SOLVER TRANSFER COMPLETE!"
log "======================================="
log ""
log "✅ Step completed successfully:"
log "   1. Solver (Solver) transferred tokens to requester (Requester) on Chain 2"
log "   2. Transfer verified by balance checks"
log "   3. Transaction hash captured for verifier"
log ""
log "📋 Transfer Details:"
log "   Intent ID: $INTENT_ID"
log "   Transaction Hash: $TX_HASH"
log "   Amount Transferred: $TRANSFER_AMOUNT Octas"
log "   Recipient: $REQUESTER_CHAIN2_ADDRESS"

