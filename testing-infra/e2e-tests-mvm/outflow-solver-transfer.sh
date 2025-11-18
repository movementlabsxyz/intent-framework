#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-outflow-solver-transfer"
cd "$PROJECT_ROOT"

# Load INTENT_ID from info file created by submit-outflow-hub-intent.sh
if ! load_intent_info "INTENT_ID"; then
    exit 1
fi

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

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"

# Get APT metadata on Chain 2 (connected chain)
log ""
log "   - Getting APT metadata on Chain 2..."
APT_METADATA_CHAIN2=$(extract_apt_metadata "bob-chain2" "$CHAIN2_ADDRESS" "$BOB_CHAIN2_ADDRESS" "2" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 2: $APT_METADATA_CHAIN2"

# Check and display initial balances
log ""
log "📊 Initial Balances:"
display_balances_connected_apt
log_and_echo ""

# Get initial balances for verification
ALICE_INITIAL_BALANCE=$(aptos account balance --profile alice-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
BOB_INITIAL_BALANCE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")

log "   Alice Chain 2 initial balance: $ALICE_INITIAL_BALANCE Octas"
log "   Bob Chain 2 initial balance: $BOB_INITIAL_BALANCE Octas"

# Amount to transfer (matches the desired_amount in the outflow intent)
TRANSFER_AMOUNT="100000000"

log ""
log "   Executing solver transfer on connected chain..."
log "   - Solver (Bob) transfers tokens directly to Alice on Chain 2"
log "   - This is a DIRECT TRANSFER, not an escrow"
log "   - Alice receives tokens immediately"
log "   - Amount: $TRANSFER_AMOUNT Octas"
log "   - Intent ID included in transaction for verifier tracking"

# Call utils::transfer_with_intent_id on Chain 2
# Parameters: sender (Bob), recipient (Alice), metadata, amount, intent_id
aptos move run --profile bob-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::utils::transfer_with_intent_id" \
    --args "address:${ALICE_CHAIN2_ADDRESS}" "address:${APT_METADATA_CHAIN2}" "u64:${TRANSFER_AMOUNT}" "address:${INTENT_ID}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Solver transfer completed on Chain 2!"

    # Wait for transaction to be processed
    sleep 2

    # Get the transaction hash from Bob's latest transaction
    log "     - Extracting transaction hash..."
    TX_HASH=$(curl -s "http://127.0.0.1:8082/v1/accounts/${BOB_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].hash' | head -n 1)

    if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
        log "     ✅ Transaction hash: $TX_HASH"

        # Verify the transfer by checking balances
        log "     - Verifying transfer by checking balances..."
        ALICE_FINAL_BALANCE=$(aptos account balance --profile alice-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
        BOB_FINAL_BALANCE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")

        log "     Alice Chain 2 final balance: $ALICE_FINAL_BALANCE Octas"
        log "     Bob Chain 2 final balance: $BOB_FINAL_BALANCE Octas"

        # Calculate expected balances (account for gas fees on Bob's side)
        ALICE_EXPECTED=$((ALICE_INITIAL_BALANCE + TRANSFER_AMOUNT))

        # Verify Alice received the tokens
        if [ "$ALICE_FINAL_BALANCE" -eq "$ALICE_EXPECTED" ]; then
            log "     ✅ Alice balance increased by $TRANSFER_AMOUNT as expected"
        else
            log_and_echo "     ⚠️  WARNING: Alice balance mismatch"
            log_and_echo "        Expected: $ALICE_EXPECTED Octas"
            log_and_echo "        Got: $ALICE_FINAL_BALANCE Octas"
        fi

        # Verify Bob's balance decreased (should be less than or equal to initial - transfer_amount due to gas)
        if [ "$BOB_FINAL_BALANCE" -le "$((BOB_INITIAL_BALANCE - TRANSFER_AMOUNT))" ]; then
            BOB_DECREASE=$((BOB_INITIAL_BALANCE - BOB_FINAL_BALANCE))
            log "     ✅ Bob balance decreased by $BOB_DECREASE Octas (transfer + gas)"
        else
            log_and_echo "     ⚠️  WARNING: Bob balance did not decrease as expected"
            log_and_echo "        Initial: $BOB_INITIAL_BALANCE Octas"
            log_and_echo "        Final: $BOB_FINAL_BALANCE Octas"
        fi

        # Save transaction hash to file for verifier to use
        TRANSFER_INFO_FILE="${PROJECT_ROOT}/.test-data/outflow-transfer-info.txt"
        mkdir -p "${PROJECT_ROOT}/.test-data"
        echo "CONNECTED_CHAIN_TX_HASH=$TX_HASH" > "$TRANSFER_INFO_FILE"
        echo "INTENT_ID=$INTENT_ID" >> "$TRANSFER_INFO_FILE"
        log "     ✅ Transaction info saved to $TRANSFER_INFO_FILE"

        log_and_echo "✅ Solver transfer completed"
    else
        log_and_echo "     ❌ ERROR: Could not extract transaction hash"
        exit 1
    fi
else
    log_and_echo "     ❌ Solver transfer failed on Chain 2!"
    log_and_echo "   Log file contents:"
    cat "$LOG_FILE"
    exit 1
fi

log ""
log "🎉 SOLVER TRANSFER COMPLETE!"
log "============================"
log ""
log "✅ Step completed successfully:"
log "   1. Solver (Bob) transferred tokens to Alice on Chain 2"
log "   2. Transfer verified by balance checks"
log "   3. Transaction hash captured for verifier"
log ""
log "📋 Transfer Details:"
log "   Intent ID: $INTENT_ID"
log "   Transaction Hash: $TX_HASH"
log "   Amount Transferred: $TRANSFER_AMOUNT Octas"
log "   Recipient: $ALICE_CHAIN2_ADDRESS"

# Check final balances using common function
log ""
display_balances_connected_apt
log_and_echo ""

