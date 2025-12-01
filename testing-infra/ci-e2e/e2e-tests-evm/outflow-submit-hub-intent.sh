#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-outflow-hub-intent-evm"
cd "$PROJECT_ROOT"

# ============================================================================
# SECTION 1: LOAD DEPENDENCIES
# ============================================================================
# Generate a random intent_id for the outflow intent
INTENT_ID="0x$(openssl rand -hex 32)"

# ============================================================================
# SECTION 2: GET ADDRESSES AND CONFIGURATION
# ============================================================================
CONNECTED_CHAIN_ID=31337
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1")
REQUESTER_CHAIN1_ADDRESS=$(get_profile_address "requester-chain1")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")

# Get EVM addresses and USDxyz token
REQUESTER_EVM_ADDRESS=$(get_hardhat_account_address "1")
SOLVER_EVM_ADDRESS=$(get_hardhat_account_address "2")
source "$PROJECT_ROOT/tmp/chain-info.env" 2>/dev/null || true
USDXYZ_ADDRESS="$USDXYZ_EVM_ADDRESS"

log ""
log "📋 Chain Information:"
log "   Hub Chain Module Address (Chain 1):     $CHAIN1_ADDRESS"
log "   Requester Chain 1 (hub):     $REQUESTER_CHAIN1_ADDRESS"
log "   Solver Chain 1 (hub):       $SOLVER_CHAIN1_ADDRESS"
log "   Requester EVM (connected): $REQUESTER_EVM_ADDRESS"
log "   Solver EVM (connected): $SOLVER_EVM_ADDRESS"

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
OFFERED_AMOUNT="100000000"  # 1 USDxyz = 100_000_000 (8 decimals, on hub chain)
DESIRED_AMOUNT="100000000"  # 1 USDxyz = 100_000_000 (8 decimals, on EVM chain)
OFFERED_CHAIN_ID=1
DESIRED_CHAIN_ID=$CONNECTED_CHAIN_ID
HUB_CHAIN_ID=1

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Verifier public key: $VERIFIER_PUBLIC_KEY"
log "   Offered amount: $OFFERED_AMOUNT USDxyz.10e8 (1 USDxyz on hub chain)"
log "   Desired amount: $DESIRED_AMOUNT USDxyz.10e8 (1 USDxyz on EVM chain)"

log ""
log "   - Getting USDxyz metadata addresses..."
log "     Getting USDxyz metadata on Chain 1..."
OFFERED_METADATA_CHAIN1=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN1" "1")
log "     ✅ Got USDxyz metadata on Chain 1: $OFFERED_METADATA_CHAIN1"

# For EVM outflow, we use Chain 1 metadata for desired (since we're transferring on EVM, not Chain 2)
DESIRED_METADATA_CHAIN1="$OFFERED_METADATA_CHAIN1"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Creating outflow request-intent on hub chain..."
log "   - Requester (Requester) creates outflow request-intent on Chain 1 (hub chain)"
log "   - Requester (Requester) locks 1 USDxyz on hub chain"
log "   - Requester (Requester) wants 1 USDxyz on connected chain (EVM Chain 3)"
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
# Register with EVM address (Solver's EVM address) and no connected chain MVM address
register_solver "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY" "$SOLVER_EVM_ADDRESS" "" "$LOG_FILE"

log "   - Waiting for solver registration to be confirmed on-chain (5 seconds)..."
sleep 5

log "   - Verifying solver registration..."
verify_solver_registered "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_CHAIN1_ADDRESS" "$LOG_FILE"

log "   - Creating outflow request-intent on Chain 1..."
log "     Offered metadata (hub): $OFFERED_METADATA_CHAIN1"
log "     Desired metadata (connected): $DESIRED_METADATA_CHAIN1"
log "     Solver (Solver) address: $SOLVER_CHAIN1_ADDRESS"
log "     Requester address on connected chain: $REQUESTER_EVM_ADDRESS"

SOLVER_SIGNATURE_HEX="${SOLVER_SIGNATURE#0x}"
VERIFIER_PUBLIC_KEY_HEX="${VERIFIER_PUBLIC_KEY#0x}"

aptos move run --profile requester-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::create_outflow_request_intent_entry" \
    --args "address:${OFFERED_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "address:${DESIRED_METADATA_CHAIN1}" "u64:${DESIRED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${REQUESTER_EVM_ADDRESS}" "hex:${VERIFIER_PUBLIC_KEY_HEX}" "address:${SOLVER_CHAIN1_ADDRESS}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Outflow request-intent created on Chain 1!"

    sleep 2
    log "     - Verifying request-intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${REQUESTER_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_address' | head -n 1)

    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub outflow request-intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Outflow request-intent created"
    else
        log_and_echo "❌ ERROR: Could not verify hub outflow request-intent address"
        exit 1
    fi
else
    log_and_echo "❌ Outflow request-intent creation failed on Chain 1!"
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
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""

log ""
log "🎉 OUTFLOW - HUB CHAIN REQUEST-INTENT CREATION COMPLETE!"
log "========================================================"
log ""
log "✅ Step completed successfully:"
log "   1. Outflow request-intent created on Chain 1 (hub chain)"
log "   2. Tokens locked on hub chain"
log ""
log "📋 Request-intent Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Outflow Request-intent: $HUB_INTENT_ADDRESS"
fi
log "   Requester address on connected chain: $REQUESTER_EVM_ADDRESS"

save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"

