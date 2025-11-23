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

TRANSFER_AMOUNT="100000000"  # 1 APT (half of Bob's 200000000 Octas)

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Transfer Amount: $TRANSFER_AMOUNT Octas (1 ETH)"

log ""
log "   - Getting APT metadata on Chain 2..."
APT_METADATA_CHAIN2=$(extract_apt_metadata "bob-chain2" "$CHAIN2_ADDRESS" "$BOB_CHAIN2_ADDRESS" "2" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 2: $APT_METADATA_CHAIN2"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_connected_mvm
log_and_echo ""

ALICE_INITIAL_BALANCE=$(aptos account balance --profile alice-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
BOB_INITIAL_BALANCE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")

log "   Alice Chain 2 initial balance: $ALICE_INITIAL_BALANCE Octas"
log "   Bob Chain 2 initial balance: $BOB_INITIAL_BALANCE Octas"

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Executing solver transfer on connected chain..."
log "   - Solver (Bob) transfers tokens directly to requester (Alice) on Chain 2"
log "   - This is a DIRECT TRANSFER, not an escrow"
log "   - Requester (Alice) receives tokens immediately on Chain 2"
log "   - Amount: $TRANSFER_AMOUNT Octas"
log "   - Intent ID included in transaction for verifier tracking"

aptos move run --profile bob-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::utils::transfer_with_intent_id" \
    --args "address:${ALICE_CHAIN2_ADDRESS}" "address:${APT_METADATA_CHAIN2}" "u64:${TRANSFER_AMOUNT}" "address:${INTENT_ID}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Solver transfer completed on Chain 2!"

    sleep 2

    log "     - Extracting transaction hash..."
    TX_HASH=$(curl -s "http://127.0.0.1:8082/v1/accounts/${BOB_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].hash' | head -n 1)

    if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
        log_and_echo "❌ ERROR: Could not extract transaction hash"
        exit 1
    fi

    log "     ✅ Transaction hash: $TX_HASH"

    log "     - Verifying transfer by checking balances..."
    ALICE_FINAL_BALANCE=$(aptos account balance --profile alice-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
    BOB_FINAL_BALANCE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")

    log "     Alice Chain 2 final balance: $ALICE_FINAL_BALANCE Octas"
    log "     Bob Chain 2 final balance: $BOB_FINAL_BALANCE Octas"

    ALICE_EXPECTED=$((ALICE_INITIAL_BALANCE + TRANSFER_AMOUNT))

    if [ "$ALICE_FINAL_BALANCE" -eq "$ALICE_EXPECTED" ]; then
        log "     ✅ Requester (Alice) Chain 2 balance increased by $TRANSFER_AMOUNT as expected"
    else
        log_and_echo "❌ ERROR: Requester (Alice) Chain 2 balance mismatch"
        log_and_echo "   Expected: $ALICE_EXPECTED Octas"
        log_and_echo "   Got: $ALICE_FINAL_BALANCE Octas"
        exit 1
    fi

    if [ "$BOB_FINAL_BALANCE" -le "$((BOB_INITIAL_BALANCE - TRANSFER_AMOUNT))" ]; then
        BOB_DECREASE=$((BOB_INITIAL_BALANCE - BOB_FINAL_BALANCE))
        log "     ✅ Solver (Bob) Chain 2 balance decreased by $BOB_DECREASE Octas (transfer + gas)"
    else
        log_and_echo "❌ ERROR: Solver (Bob) Chain 2 balance did not decrease as expected"
        log_and_echo "   Initial: $BOB_INITIAL_BALANCE Octas"
        log_and_echo "   Final: $BOB_FINAL_BALANCE Octas"
        exit 1
    fi

    TRANSFER_INFO_FILE="${PROJECT_ROOT}/.test-data/outflow-transfer-info.txt"
    mkdir -p "${PROJECT_ROOT}/.test-data"
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
display_balances_connected_mvm
log_and_echo ""

log ""
log "🎉 OUTFLOW - SOLVER TRANSFER COMPLETE!"
log "======================================="
log ""
log "✅ Step completed successfully:"
log "   1. Solver (Bob) transferred tokens to requester (Alice) on Chain 2"
log "   2. Transfer verified by balance checks"
log "   3. Transaction hash captured for verifier"
log ""
log "📋 Transfer Details:"
log "   Intent ID: $INTENT_ID"
log "   Transaction Hash: $TX_HASH"
log "   Amount Transferred: $TRANSFER_AMOUNT Octas"
log "   Recipient: $ALICE_CHAIN2_ADDRESS"

