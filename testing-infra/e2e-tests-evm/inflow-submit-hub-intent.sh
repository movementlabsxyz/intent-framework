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
source "$PROJECT_ROOT/tmp/chain-info.env" 2>/dev/null || true
USDXYZ_EVM_ADDRESS="${USDXYZ_EVM_ADDRESS:-}"

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Requester Chain 1 (hub):     $REQUESTER_CHAIN1_ADDRESS"
log "   Solver Chain 1 (hub):       $SOLVER_CHAIN1_ADDRESS"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"

# Check and display initial balances using common function
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_EVM_ADDRESS"
log_and_echo ""

log ""
log "   Creating intent on hub chain..."
log "   - Requester creates intent on Chain 1 (hub chain)"
log "   - Intent requests 1 USDxyz to be provided by solver (on hub chain)"
log "   - Using intent_id: $INTENT_ID"
log "   - Connected chain: EVM (Chain ID: 31337)"

# Get USDxyz metadata addresses
log "   - Getting USDxyz metadata addresses..."

# Get USDxyz metadata on Chain 1 (hub)
log "     Getting USDxyz metadata on Chain 1..."
USDXYZ_METADATA_CHAIN1=$(get_usdxyz_metadata "0x$TEST_TOKENS_CHAIN1" "1")
log "     ✅ Got USDxyz metadata on Chain 1: $USDXYZ_METADATA_CHAIN1"
OFFERED_METADATA_CHAIN1="$USDXYZ_METADATA_CHAIN1"
DESIRED_METADATA_CHAIN1="$USDXYZ_METADATA_CHAIN1"

# In EVM mode, use Chain 1 metadata for signature generation (escrow is on EVM)
OFFERED_METADATA_CHAIN2="$USDXYZ_METADATA_CHAIN1"

# Create cross-chain request-intent on Chain 1 using fa_intent module
# NOTE: Cross-chain request-intents must be reserved. This requires:
# 1. Off-chain negotiation with solver (Solver)
# 2. Solver signs IntentToSign structure (BCS-encoded)
# 3. Pass solver address and signature to create_inflow_request_intent
#
# In production, the solver would sign off-chain using their private key.
# For e2e tests, we can use the utils::get_intent_to_sign_hash function to get the hash:
# 1. Call utils::get_intent_to_sign_hash() to get the BCS-encoded hash via event
# 2. Sign the hash with Ed25519 using Solver's private key (requires helper script)
# 3. Convert signature to hex format
# 4. Use the signature in create_inflow_request_intent (solver must be registered in registry)
#
log "   - Creating cross-chain request-intent on Chain 1..."
log "     Offered metadata: $OFFERED_METADATA_CHAIN1"
log "     Desired metadata: $DESIRED_METADATA_CHAIN1"
log "     Solver (Solver) address: $SOLVER_CHAIN1_ADDRESS"
log "     Generating solver signature..."

# Generate solver signature using helper function
# For cross-chain intents: offered tokens are on connected chain, desired tokens are on hub chain (chain 1)
OFFERED_AMOUNT="100000000"  # 1 USDxyz = 100_000_000 (on EVM chain)
DESIRED_AMOUNT="100000000"  # 1 USDxyz = 100_000_000 (on hub chain)
OFFERED_CHAIN_ID=$CONNECTED_CHAIN_ID  # Connected chain where escrow will be created (31337 for EVM)
DESIRED_CHAIN_ID=1  # Hub chain where intent is created
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
    log_and_echo "     ❌ Failed to generate solver signature"
    log_and_echo "     Output was: $SOLVER_SIGNATURE"
    exit 1
fi

log "     ✅ Solver signature generated: ${SOLVER_SIGNATURE:0:20}..."

# Extract public key from log file (sign_intent outputs it to stderr with "PUBLIC_KEY:" prefix)
SOLVER_PUBLIC_KEY=$(grep "PUBLIC_KEY:" "$LOG_FILE" | tail -1 | sed 's/.*PUBLIC_KEY://')
if [ -z "$SOLVER_PUBLIC_KEY" ]; then
    log_and_echo "     ❌ Failed to extract solver public key from sign_intent output"
    exit 1
fi
log "     ✅ Solver public key extracted: ${SOLVER_PUBLIC_KEY:0:20}..."

# Register solver in the solver registry before creating intent
# Use a simple test EVM address (20 bytes: 0x0000...0001)
EVM_ADDRESS="0x0000000000000000000000000000000000000001"
log "     Registering solver (Solver) in solver registry..."
# register_solver: profile, chain_address, public_key_hex, evm_address_hex, [connected_chain_mvm_address], [log_file]
register_solver "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY" "$EVM_ADDRESS" "" "$LOG_FILE"

log "     - Waiting for solver registration to be confirmed on-chain (5 seconds)..."
sleep 5

log "     - Verifying solver registration..."
verify_solver_registered "solver-chain1" "$CHAIN1_ADDRESS" "$SOLVER_CHAIN1_ADDRESS" "$LOG_FILE"

# Remove 0x prefix from signature for hex format
SOLVER_SIGNATURE_HEX="${SOLVER_SIGNATURE#0x}"
HUB_CHAIN_ID=1
aptos move run --profile requester-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_inflow::create_inflow_request_intent_entry" \
    --args "address:${OFFERED_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "address:${DESIRED_METADATA_CHAIN1}" "u64:${DESIRED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${SOLVER_CHAIN1_ADDRESS}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Intent created on Chain 1!"
    
    # Verify intent was stored on-chain by checking Requester's latest transaction
    sleep 2
    log "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${REQUESTER_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent")) | .data.intent_address' | head -n 1)
    
    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Intent created"
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

log ""
log "🎉 HUB CHAIN INTENT CREATION COMPLETE!"
log "======================================="
log ""
log "✅ Step completed successfully:"
log "   1. Intent created on Chain 1 (hub chain)"
log ""
log "📋 Intent Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Intent: $HUB_INTENT_ADDRESS"
fi

# Export values for use by other scripts
save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"

# Check final balances using common function
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_EVM_ADDRESS"
log_and_echo ""

