#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-escrow"
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

# Load verifier keys (generated during deployment)
load_verifier_keys

# Get public key from environment variable
VERIFIER_PUBLIC_KEY_B64="${E2E_VERIFIER_PUBLIC_KEY}"

if [ -z "$VERIFIER_PUBLIC_KEY_B64" ]; then
    log_and_echo "❌ ERROR: E2E_VERIFIER_PUBLIC_KEY environment variable not set"
    log_and_echo "   The verifier public key is required for escrow creation."
    log_and_echo "   Please ensure E2E_VERIFIER_PUBLIC_KEY is set (generate_verifier_keys should do this)."
    exit 1
fi

ORACLE_PUBLIC_KEY_HEX=$(echo "$VERIFIER_PUBLIC_KEY_B64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')

if [ -z "$ORACLE_PUBLIC_KEY_HEX" ] || [ ${#ORACLE_PUBLIC_KEY_HEX} -ne 64 ]; then
    log_and_echo "❌ ERROR: Invalid public key format"
    log_and_echo "   Expected: base64-encoded 32-byte Ed25519 public key"
    log_and_echo "   Got: $VERIFIER_PUBLIC_KEY_B64"
    log_and_echo "   Please ensure E2E_VERIFIER_PUBLIC_KEY is valid base64 and decodes to 32 bytes (64 hex chars)."
    exit 1
fi

ORACLE_PUBLIC_KEY="0x${ORACLE_PUBLIC_KEY_HEX}"
EXPIRY_TIME=$(date -d "+1 hour" +%s)
CONNECTED_CHAIN_ID=2
HUB_CHAIN_ID=1

log ""
log "🔑 Configuration:"
log "   Verifier public key: $ORACLE_PUBLIC_KEY"
log "   Expiry time: $EXPIRY_TIME"
log "   Intent ID: $INTENT_ID"

log ""
log "   - Getting USDcon metadata on Chain 2..."
USDCON_METADATA_CHAIN2=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN2" "2")
if [ -z "$USDCON_METADATA_CHAIN2" ]; then
    log_and_echo "❌ Failed to get USDcon metadata on Chain 2"
    exit 1
fi
log "     ✅ Got USDcon metadata on Chain 2: $USDCON_METADATA_CHAIN2"
OFFERED_METADATA_CHAIN2="$USDCON_METADATA_CHAIN2"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_mvm "0x$TEST_TOKENS_CHAIN2"
log_and_echo ""

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Creating escrow on connected chain..."
log "   - Requester (Requester) locks 1 USDcon in escrow on Chain 2 (connected chain)"
log "   - Using intent_id from hub chain: $INTENT_ID"

# DEBUG: Check requester balance BEFORE escrow creation
log ""
log "   DEBUG: Checking requester balance BEFORE escrow creation..."
BEFORE_BALANCE=$(get_usdxyz_balance "requester-chain2" "2" "0x$TEST_TOKENS_CHAIN2")
log_and_echo "   DEBUG: Requester USDcon balance BEFORE escrow: $BEFORE_BALANCE"

log "   - Creating escrow intent on Chain 2..."
log "     Offered metadata: $OFFERED_METADATA_CHAIN2"
log "     Reserved solver (Connected Chain 2 Solver): $SOLVER_CHAIN2_ADDRESS"

ESCROW_OUTPUT=$(aptos move run --profile requester-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::intent_as_escrow_entry::create_escrow_from_fa" \
    --args "address:${OFFERED_METADATA_CHAIN2}" "u64:1000000" "u64:${CONNECTED_CHAIN_ID}" "hex:${ORACLE_PUBLIC_KEY}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${SOLVER_CHAIN2_ADDRESS}" "u64:${HUB_CHAIN_ID}" 2>&1)
ESCROW_EXIT_CODE=$?

log "   DEBUG: Escrow transaction output:"
log "$ESCROW_OUTPUT"

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $ESCROW_EXIT_CODE -eq 0 ]; then
    log "     ✅ Escrow intent created on Chain 2!"

    # DEBUG: Check requester balance AFTER escrow creation
    log ""
    log "   DEBUG: Checking requester balance AFTER escrow creation..."
    AFTER_BALANCE=$(get_usdxyz_balance "requester-chain2" "2" "0x$TEST_TOKENS_CHAIN2")
    log_and_echo "   DEBUG: Requester USDcon balance AFTER escrow: $AFTER_BALANCE"
    
    if [ "$BEFORE_BALANCE" = "$AFTER_BALANCE" ]; then
        log_and_echo "   ⚠️  WARNING: Requester balance did NOT change after escrow creation!"
        log_and_echo "      Before: $BEFORE_BALANCE, After: $AFTER_BALANCE"
    else
        DIFF=$((BEFORE_BALANCE - AFTER_BALANCE))
        log_and_echo "   ✅ Requester balance decreased by: $DIFF (locked in escrow)"
    fi

    sleep 4
    log "     - Verifying escrow stored on-chain with locked tokens..."

    # Get full transaction for debugging
    FULL_TX=$(curl -s "http://127.0.0.1:8082/v1/accounts/${REQUESTER_CHAIN2_ADDRESS}/transactions?limit=1")
    
    ESCROW_ADDRESS=$(echo "$FULL_TX" | jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_addr' | head -n 1)
    ESCROW_INTENT_ID=$(echo "$FULL_TX" | jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_id' | head -n 1)
    LOCKED_AMOUNT=$(echo "$FULL_TX" | jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.offered_amount' | head -n 1)
    DESIRED_AMOUNT=$(echo "$FULL_TX" | jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.desired_amount' | head -n 1)
    
    # Output full event for debugging
    FULL_EVENT=$(echo "$FULL_TX" | jq '.[0].events[] | select(.type | contains("OracleLimitOrderEvent"))')
    log "   DEBUG: Full OracleLimitOrderEvent:"
    log "$FULL_EVENT"

    if [ -z "$ESCROW_ADDRESS" ] || [ "$ESCROW_ADDRESS" = "null" ]; then
        log_and_echo "❌ ERROR: Could not verify escrow from events"
        exit 1
    fi

    log "     ✅ Escrow stored at: $ESCROW_ADDRESS"
    log "     ✅ Intent ID link: $ESCROW_INTENT_ID (should match: $INTENT_ID)"
    log "     ✅ Locked amount: $LOCKED_AMOUNT tokens"
    log "     ✅ Desired amount: $DESIRED_AMOUNT tokens"

    NORMALIZED_INTENT_ID=$(echo "$INTENT_ID" | tr '[:upper:]' '[:lower:]' | sed 's/^0x//' | sed 's/^0*//')
    NORMALIZED_ESCROW_INTENT_ID=$(echo "$ESCROW_INTENT_ID" | tr '[:upper:]' '[:lower:]' | sed 's/^0x//' | sed 's/^0*//')

    [ -z "$NORMALIZED_INTENT_ID" ] && NORMALIZED_INTENT_ID="0"
    [ -z "$NORMALIZED_ESCROW_INTENT_ID" ] && NORMALIZED_ESCROW_INTENT_ID="0"

    if [ "$NORMALIZED_INTENT_ID" = "$NORMALIZED_ESCROW_INTENT_ID" ]; then
        log "     ✅ Intent IDs match - correct cross-chain link!"
    else
        log_and_echo "❌ ERROR: Intent IDs don't match!"
        log_and_echo "   Expected: $INTENT_ID"
        log_and_echo "   Got: $ESCROW_INTENT_ID"
        exit 1
    fi

    if [ "$LOCKED_AMOUNT" = "1000000" ]; then
        log "     ✅ Escrow has correct locked amount (1 USDcon)"
    else
        log_and_echo "❌ ERROR: Escrow has unexpected locked amount: $LOCKED_AMOUNT"
        log_and_echo "   Expected: 100_000_000 (1 USDcon)"
        exit 1
    fi

    log_and_echo "✅ Escrow created"
else
    log_and_echo "❌ Escrow intent creation failed!"
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
log "🎉 INFLOW - ESCROW CREATION COMPLETE!"
log "======================================"
log ""
log "✅ Step completed successfully:"
log "   1. Escrow created on Chain 2 (connected chain) with locked tokens"
log ""
log "📋 Escrow Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$ESCROW_ADDRESS" ] && [ "$ESCROW_ADDRESS" != "null" ]; then
    log "   Chain 2 Escrow: $ESCROW_ADDRESS"
    # Save ESCROW_ADDRESS to intent-info.env for escrow claim verification
    echo "CHAIN2_ESCROW_ADDRESS=$ESCROW_ADDRESS" >> "$PROJECT_ROOT/.tmp/intent-info.env"
fi


