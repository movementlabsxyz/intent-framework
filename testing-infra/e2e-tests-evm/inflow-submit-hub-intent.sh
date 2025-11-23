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

# Get Alice and Bob addresses
ALICE_CHAIN1_ADDRESS=$(get_profile_address "alice-chain1")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Alice Chain 1 (hub):     $ALICE_CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"

# Check and display initial balances using common function
log ""
display_balances_hub
display_balances_connected_evm
log_and_echo ""

log ""
log "   Creating intent on hub chain..."
log "   - Alice creates intent on Chain 1 (hub chain)"
log "   - Intent requests 1 APT to be provided by solver (on hub chain)"
log "   - Using intent_id: $INTENT_ID"
log "   - Connected chain: EVM (Chain ID: 31337)"

# Get APT metadata addresses for Chain 1
log "   - Getting APT metadata addresses..."

# Get APT metadata on Chain 1
log "     Getting APT metadata on Chain 1..."
APT_METADATA_CHAIN1=$(extract_apt_metadata "alice-chain1" "$CHAIN1_ADDRESS" "$ALICE_CHAIN1_ADDRESS" "1" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 1: $APT_METADATA_CHAIN1"
OFFERED_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"
DESIRED_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"

# In EVM mode, use Chain 1 metadata for both (since escrow is on EVM, not Chain 2)
OFFERED_FA_METADATA_CHAIN2="$APT_METADATA_CHAIN1"

# Create cross-chain request intent on Chain 1 using fa_intent module
# NOTE: Cross-chain request intents must be reserved. This requires:
# 1. Off-chain negotiation with solver (Bob)
# 2. Solver signs IntentToSign structure (BCS-encoded)
# 3. Pass solver address and signature to create_inflow_request_intent
#
# In production, the solver would sign off-chain using their private key.
# For e2e tests, we can use the utils::get_intent_to_sign_hash function to get the hash:
# 1. Call utils::get_intent_to_sign_hash() to get the BCS-encoded hash via event
# 2. Sign the hash with Ed25519 using Bob's private key (requires helper script)
# 3. Convert signature to hex format
# 4. Use the signature in create_inflow_request_intent (solver must be registered in registry)
#
log "   - Creating cross-chain request intent on Chain 1..."
log "     Offered FA metadata: $OFFERED_FA_METADATA_CHAIN1"
log "     Desired FA metadata: $DESIRED_FA_METADATA_CHAIN1"
log "     Solver (Bob) address: $BOB_CHAIN1_ADDRESS"
log "     Generating solver signature..."

# Generate solver signature using helper function
# For cross-chain intents: offered tokens are on connected chain, desired tokens are on hub chain (chain 1)
OFFERED_AMOUNT="1000000000000000000"  # 1 ETH (on EVM chain)
DESIRED_AMOUNT="100000000"  # 1 APT (on hub chain Chain 1)
OFFERED_CHAIN_ID=$CONNECTED_CHAIN_ID  # Connected chain where escrow will be created (31337 for EVM)
DESIRED_CHAIN_ID=1  # Hub chain where intent is created
SOLVER_SIGNATURE=$(generate_solver_signature \
    "bob-chain1" \
    "$CHAIN1_ADDRESS" \
    "$OFFERED_FA_METADATA_CHAIN1" \
    "$OFFERED_AMOUNT" \
    "$OFFERED_CHAIN_ID" \
    "$DESIRED_FA_METADATA_CHAIN1" \
    "$DESIRED_AMOUNT" \
    "$DESIRED_CHAIN_ID" \
    "$EXPIRY_TIME" \
    "$ALICE_CHAIN1_ADDRESS" \
    "$BOB_CHAIN1_ADDRESS" \
    "1" \
    "$LOG_FILE")

if [ -z "$SOLVER_SIGNATURE" ]; then
    log_and_echo "     ❌ Failed to generate solver signature"
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
log "     Registering solver (Bob) in solver registry..."
# register_solver: profile, chain_address, public_key_hex, evm_address_hex, [connected_chain_mvm_address], [log_file]
register_solver "bob-chain1" "$CHAIN1_ADDRESS" "$SOLVER_PUBLIC_KEY" "$EVM_ADDRESS" "" "$LOG_FILE"

log "     - Waiting for solver registration to be confirmed on-chain (5 seconds)..."
sleep 5

log "     - Verifying solver registration..."
verify_solver_registered "bob-chain1" "$CHAIN1_ADDRESS" "$BOB_CHAIN1_ADDRESS" "$LOG_FILE"

# Remove 0x prefix from signature for hex format
SOLVER_SIGNATURE_HEX="${SOLVER_SIGNATURE#0x}"
HUB_CHAIN_ID=1
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_inflow::create_inflow_request_intent_entry" \
    --args "address:${OFFERED_FA_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "address:${DESIRED_FA_METADATA_CHAIN1}" "u64:${DESIRED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${BOB_CHAIN1_ADDRESS}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Intent created on Chain 1!"
    
    # Verify intent was stored on-chain by checking Alice's latest transaction
    sleep 2
    log "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" | \
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
display_balances_hub
display_balances_connected_evm
log_and_echo ""

