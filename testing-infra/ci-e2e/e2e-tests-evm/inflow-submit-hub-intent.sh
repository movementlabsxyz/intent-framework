#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "inflow-submit-hub-intent-evm"
cd "$PROJECT_ROOT"

# Verify services are running before proceeding
verify_verifier_running
verify_solver_running
verify_solver_registered

# Generate a random intent_id that will be used for both hub and escrow
INTENT_ID="0x$(openssl rand -hex 32)"

# EVM mode: CONNECTED_CHAIN_ID=31337
CONNECTED_CHAIN_ID=31337

# Get addresses
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1")

# Get Requester and Solver addresses on hub
REQUESTER_CHAIN1_ADDRESS=$(get_profile_address "requester-chain1")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")

# Get Requester address on connected EVM chain (Account 1)
REQUESTER_EVM_ADDRESS=$(get_hardhat_account_address "1")
if [ -z "$REQUESTER_EVM_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Failed to get Requester EVM address (Hardhat account 1)"
    log_and_echo "   Make sure Hardhat node is running and chain-connected-evm/utils.sh is available"
    display_service_logs "Missing Requester EVM address for inflow hub intent"
    exit 1
fi

# Get USDcon EVM address
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true
USDCON_EVM_ADDRESS="${USDCON_EVM_ADDRESS:-}"

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):            $CHAIN1_ADDRESS"
log "   Requester Chain 1 (hub):        $REQUESTER_CHAIN1_ADDRESS"
log "   Solver Chain 1 (hub):           $SOLVER_CHAIN1_ADDRESS"
log "   Requester EVM (connected):      $REQUESTER_EVM_ADDRESS"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

# Generate solver signature using helper function
# For cross-chain intents: offered tokens are on connected chain, desired tokens are on hub chain (chain 1)
OFFERED_AMOUNT="1000000"  # 1 USDcon = 1_000_000 (6 decimals, on EVM connected chain)
DESIRED_AMOUNT="1000000"  # 1 USDhub = 1_000_000 (6 decimals, on hub chain)
HUB_CHAIN_ID=1
EVM_ADDRESS="0x0000000000000000000000000000000000000001"

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Offered amount: $OFFERED_AMOUNT (1 USDcon on connected EVM chain, Chain 3)"
log "   Desired amount: $DESIRED_AMOUNT (1 USDhub on hub chain, Chain 1)"

# Check and display initial balances using common function
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDCON_EVM_ADDRESS"
log_and_echo ""

# Get USDhub metadata addresses (hub) and USDcon metadata (connected) as needed
log ""
log "   - Getting USD token metadata addresses..."
log "     Getting USDhub metadata on Chain 1 (hub)..."
USDHUB_METADATA_CHAIN1=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN1" "1")
log "     ✅ Got USDhub metadata on Chain 1: $USDHUB_METADATA_CHAIN1"

# For EVM inflow: offered token is on EVM chain (connected), desired token is on hub
# Convert 20-byte Ethereum address to 32-byte Move address by padding with zeros
# Lowercase for consistent matching with solver acceptance config
EVM_TOKEN_ADDRESS_NO_PREFIX="${USDCON_EVM_ADDRESS#0x}"
EVM_TOKEN_ADDRESS_LOWER=$(echo "$EVM_TOKEN_ADDRESS_NO_PREFIX" | tr '[:upper:]' '[:lower:]')
OFFERED_METADATA_EVM="0x000000000000000000000000${EVM_TOKEN_ADDRESS_LOWER}"
DESIRED_METADATA_CHAIN1="$USDHUB_METADATA_CHAIN1"
log "     EVM USDcon token address: $USDCON_EVM_ADDRESS"
log "     Padded to 32-byte format: $OFFERED_METADATA_EVM"
log "     Inflow configuration:"
log "       Offered metadata (EVM connected chain): $OFFERED_METADATA_EVM"
log "       Desired metadata (hub chain 1): $DESIRED_METADATA_CHAIN1"

# ============================================================================
# SECTION 4: VERIFIER-BASED NEGOTIATION ROUTING
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
    "$CONNECTED_CHAIN_ID" \
    "$DESIRED_METADATA_CHAIN1" \
    "$DESIRED_AMOUNT" \
    "$HUB_CHAIN_ID" \
    "$EXPIRY_TIME" \
    "$INTENT_ID" \
    "$REQUESTER_CHAIN1_ADDRESS" \
    "{\"chain_addr\": \"$CHAIN1_ADDRESS\", \"flow_type\": \"inflow\", \"connected_chain_type\": \"evm\"}")

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
RETRIEVED_SOLVER=$(echo "$SIGNATURE_DATA" | jq -r '.solver_addr')

if [ -z "$RETRIEVED_SIGNATURE" ] || [ "$RETRIEVED_SIGNATURE" = "null" ]; then
    log_and_echo "❌ ERROR: Failed to retrieve signature from verifier"
    log_and_echo ""
    log_and_echo "🔍 Diagnostics:"
    
    # Check if solver is running
    SOLVER_LOG_FILE="$PROJECT_ROOT/.tmp/e2e-tests/solver.log"
    if [ -f "$PROJECT_ROOT/.tmp/e2e-tests/solver.pid" ]; then
        SOLVER_PID=$(cat "$PROJECT_ROOT/.tmp/e2e-tests/solver.pid")
        if ps -p "$SOLVER_PID" > /dev/null 2>&1; then
            log_and_echo "   ✅ Solver process is running (PID: $SOLVER_PID)"
        else
            log_and_echo "   ❌ Solver process is NOT running (PID: $SOLVER_PID)"
        fi
    else
        log_and_echo "   ❌ Solver PID file not found"
    fi
    
    # Show solver log
    if [ -f "$SOLVER_LOG_FILE" ]; then
        log_and_echo ""
        log_and_echo "   📋 Solver log (last 100 lines):"
        log_and_echo "   ----------------------------------------"
        tail -100 "$SOLVER_LOG_FILE" | while read line; do log_and_echo "   $line"; done
        log_and_echo "   ----------------------------------------"
    else
        log_and_echo "   ⚠️  Solver log file not found: $SOLVER_LOG_FILE"
    fi
    
    # Show verifier log
    VERIFIER_LOG_FILE="$PROJECT_ROOT/.tmp/e2e-tests/verifier.log"
    if [ -f "$VERIFIER_LOG_FILE" ]; then
        log_and_echo ""
        log_and_echo "   📋 Verifier log (last 30 lines):"
        log_and_echo "   ----------------------------------------"
        tail -30 "$VERIFIER_LOG_FILE" | while read line; do log_and_echo "   $line"; done
        log_and_echo "   ----------------------------------------"
    fi
    
    exit 1
fi
log "     ✅ Retrieved signature from solver: $RETRIEVED_SOLVER"
log "     Signature: ${RETRIEVED_SIGNATURE:0:20}..."

# ============================================================================
# SECTION 5: CREATE INTENT ON-CHAIN WITH RETRIEVED SIGNATURE
# ============================================================================
log ""
log "   Creating cross-chain intent on Chain 1..."
log "     Offered metadata: $OFFERED_METADATA_EVM"
log "     Desired metadata: $DESIRED_METADATA_CHAIN1"
log "     Solver address: $RETRIEVED_SOLVER"

SOLVER_SIGNATURE_HEX="${RETRIEVED_SIGNATURE#0x}"
aptos move run --profile requester-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_inflow::create_inflow_intent_entry" \
    --args "address:${OFFERED_METADATA_EVM}" "u64:${OFFERED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "address:${DESIRED_METADATA_CHAIN1}" "u64:${DESIRED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${RETRIEVED_SOLVER}" "hex:${SOLVER_SIGNATURE_HEX}" "address:${REQUESTER_EVM_ADDRESS}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 6: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Intent created on Chain 1!"
    
    # Verify intent was stored on-chain by checking Requester's latest transaction
    sleep 2
    log "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${REQUESTER_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent")) | .data.intent_addr' | head -n 1)
    
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
    # Include service logs (verifier/solver) for easier debugging
    display_service_logs "EVM inflow hub intent creation failed"
    exit 1
fi

# ============================================================================
# SECTION 7: FINAL SUMMARY
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
display_balances_connected_evm "$USDCON_EVM_ADDRESS"
log_and_echo ""

