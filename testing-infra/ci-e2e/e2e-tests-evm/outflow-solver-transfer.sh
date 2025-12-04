#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-outflow-solver-transfer-evm"
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
REQUESTER_EVM_ADDRESS=$(get_hardhat_account_address "1")
SOLVER_EVM_ADDRESS=$(get_hardhat_account_address "2")

log ""
log "📋 Chain Information:"
log "   Requester EVM (connected): $REQUESTER_EVM_ADDRESS"
log "   Solver EVM (connected): $SOLVER_EVM_ADDRESS"

# Transfer amount must match the intent's desired_amount (1 USDxyz)
# This is the amount the requester specified they want on the connected chain
TRANSFER_AMOUNT="1000000"  # 1 USDxyz = 1_000_000 (6 decimals)

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Transfer Amount: $TRANSFER_AMOUNT USDxyz.10e8 (matches intent desired_amount)"

# Get USDxyz token address from chain-info.env
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true
USDXYZ_ADDRESS="$USDXYZ_EVM_ADDRESS"

if [ -z "$USDXYZ_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not find USDxyz token address"
    log_and_echo "   Make sure deploy-contract.sh has been run for EVM chain"
    exit 1
fi

log "   - Using USDxyz token: $USDXYZ_ADDRESS"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""

# Get initial token balances
cd evm-intent-framework
REQUESTER_CHAIN3_TOKEN_INIT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' ACCOUNT='$REQUESTER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1 | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
SOLVER_CHAIN3_TOKEN_INIT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' ACCOUNT='$SOLVER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1 | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
cd ..

log "   Requester Chain 3 token balance (initial): $REQUESTER_CHAIN3_TOKEN_INIT"
log "   Solver Chain 3 token balance (initial): $SOLVER_CHAIN3_TOKEN_INIT"

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Executing solver transfer on connected EVM chain..."
log "   - Solver (Solver) transfers tokens directly to requester (Requester) on EVM chain"
log "   - This is a DIRECT TRANSFER, not an escrow"
log "   - Requester (Requester) receives tokens immediately on EVM chain"
log "   - Amount: $TRANSFER_AMOUNT USDxyz.10e8 (matches intent desired_amount)"
log "   - Intent ID included in transaction calldata for verifier tracking"

cd evm-intent-framework

# Convert intent_id to EVM format
INTENT_ID_EVM=$(convert_intent_id_to_evm "$INTENT_ID")

TRANSFER_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' RECIPIENT='$REQUESTER_EVM_ADDRESS' AMOUNT='$TRANSFER_AMOUNT' INTENT_ID='$INTENT_ID_EVM' npx hardhat run scripts/transfer-with-intent-id.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
TRANSFER_EXIT_CODE=$?

cd ..

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $TRANSFER_EXIT_CODE -eq 0 ] && echo "$TRANSFER_OUTPUT" | grep -qi "SUCCESS"; then
    log "     ✅ Solver transfer completed on EVM chain!"

    # Extract transaction hash from output
    TX_HASH=$(echo "$TRANSFER_OUTPUT" | grep -i "Transaction hash:" | awk '{print $NF}' | tr -d '\n')
    
    if [ -z "$TX_HASH" ]; then
        # Try to get from hardhat output or query latest transaction
        sleep 2
        TX_HASH=$(curl -s -X POST http://127.0.0.1:8545 \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":["'$(curl -s -X POST http://127.0.0.1:8545 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_getTransactionByBlockNumberAndIndex","params":["latest","0x0"],"id":1}' | jq -r '.result.hash')'"],"id":1}' | jq -r '.result.hash' 2>/dev/null || echo "")
    fi

    if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
        log_and_echo "❌ ERROR: Could not extract transaction hash"
        exit 1
    fi

    log "     ✅ Transaction hash: $TX_HASH"

    sleep 2

    log "     - Verifying transfer by checking token balances..."
    cd evm-intent-framework
    REQUESTER_CHAIN3_TOKEN_FINAL=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' ACCOUNT='$REQUESTER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1 | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
    SOLVER_CHAIN3_TOKEN_FINAL=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' ACCOUNT='$SOLVER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1 | grep -E '^[0-9]+$' | tail -1 | tr -d '\n' || echo "0")
    cd ..

    log "     Requester Chain 3 token balance (final): $REQUESTER_CHAIN3_TOKEN_FINAL"
    log "     Solver Chain 3 token balance (final): $SOLVER_CHAIN3_TOKEN_FINAL"

    REQUESTER_CHAIN3_TOKEN_EXPECTED=$(echo "$REQUESTER_CHAIN3_TOKEN_INIT + $TRANSFER_AMOUNT" | bc)
    REQUESTER_CHAIN3_TOKEN_INCREASE=$(echo "$REQUESTER_CHAIN3_TOKEN_FINAL - $REQUESTER_CHAIN3_TOKEN_INIT" | bc)

    # Use bc for comparison since wei values exceed bash integer limits
    # Token balance should increase by exactly the transfer amount (gas fees don't affect token balances)
    BALANCE_MATCH=$(echo "$REQUESTER_CHAIN3_TOKEN_FINAL == $REQUESTER_CHAIN3_TOKEN_EXPECTED" | bc)
    INCREASE_MATCH=$(echo "$REQUESTER_CHAIN3_TOKEN_INCREASE == $TRANSFER_AMOUNT" | bc)

    if [ "$BALANCE_MATCH" -eq 1 ] || [ "$INCREASE_MATCH" -eq 1 ]; then
        log "     ✅ Requester (Requester) Chain 3 token balance increased by $REQUESTER_CHAIN3_TOKEN_INCREASE as expected"
    else
        log_and_echo "❌ ERROR: Requester (Requester) Chain 3 token balance mismatch"
        log_and_echo "   Expected Chain 3 final balance: $REQUESTER_CHAIN3_TOKEN_EXPECTED"
        log_and_echo "   Got Chain 3 final balance: $REQUESTER_CHAIN3_TOKEN_FINAL"
        log_and_echo "   Expected increase: $TRANSFER_AMOUNT USDxyz.10e8"
        log_and_echo "   Got increase: $REQUESTER_CHAIN3_TOKEN_INCREASE"
        exit 1
    fi

    TRANSFER_INFO_FILE="${PROJECT_ROOT}/.tmp/outflow-transfer-info.txt"
    mkdir -p "${PROJECT_ROOT}/tmp"
    echo "CONNECTED_CHAIN_TX_HASH=$TX_HASH" > "$TRANSFER_INFO_FILE"
    echo "INTENT_ID=$INTENT_ID" >> "$TRANSFER_INFO_FILE"
    log "     ✅ Transaction info saved to $TRANSFER_INFO_FILE"

    log_and_echo "✅ Solver transfer completed"
else
    log_and_echo "❌ Solver transfer failed on EVM chain!"
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
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""

log ""
log "🎉 OUTFLOW - SOLVER TRANSFER COMPLETE!"
log "======================================="
log ""
log "✅ Step completed successfully:"
log "   1. Solver (Solver) transferred tokens to requester (Requester) on EVM chain"
log "   2. Transfer verified by token balance checks"
log "   3. Transaction hash captured for verifier"
log ""
log "📋 Transfer Details:"
log "   Intent ID: $INTENT_ID"
log "   Transaction Hash: $TX_HASH"
log "   Amount Transferred: $TRANSFER_AMOUNT USDxyz.10e8 (matches intent desired_amount)"
log "   Recipient: $REQUESTER_EVM_ADDRESS"
log "   Token Address: $USDXYZ_ADDRESS"

