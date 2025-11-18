#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-outflow-hub-intent"
cd "$PROJECT_ROOT"

# Generate a random intent_id for the outflow intent
INTENT_ID="0x$(openssl rand -hex 32)"

# Aptos mode: CONNECTED_CHAIN_ID=2
CONNECTED_CHAIN_ID=2

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

# Load oracle public key from verifier config (base64 encoded, needs to be converted to hex)
# Use verifier_testing.toml for tests - required, panic if not found
VERIFIER_TESTING_CONFIG="${PROJECT_ROOT}/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

# Export config path for Rust code to use (if called)
export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

VERIFIER_PUBLIC_KEY_B64=$(grep "^public_key" "$VERIFIER_TESTING_CONFIG" | cut -d'"' -f2)

if [ -z "$VERIFIER_PUBLIC_KEY_B64" ]; then
    log_and_echo "❌ ERROR: Could not find public_key in verifier_testing.toml"
    log_and_echo "   The verifier public key is required for outflow intent creation."
    log_and_echo "   Please ensure verifier_testing.toml has a valid public_key field."
    exit 1
fi

# Convert base64 public key to hex (32 bytes)
VERIFIER_PUBLIC_KEY_HEX=$(echo "$VERIFIER_PUBLIC_KEY_B64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')

if [ -z "$VERIFIER_PUBLIC_KEY_HEX" ] || [ ${#VERIFIER_PUBLIC_KEY_HEX} -ne 64 ]; then
    log_and_echo "❌ ERROR: Invalid public key format in verifier_testing.toml"
    log_and_echo "   Expected: base64-encoded 32-byte Ed25519 public key"
    log_and_echo "   Got: $VERIFIER_PUBLIC_KEY_B64"
    log_and_echo "   Please ensure the public_key in verifier_testing.toml is valid base64 and decodes to 32 bytes (64 hex chars)."
    exit 1
fi

VERIFIER_PUBLIC_KEY="0x${VERIFIER_PUBLIC_KEY_HEX}"
log "   ✅ Loaded verifier public key from config (32 bytes)"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"
log "   Verifier public key: $VERIFIER_PUBLIC_KEY"

# Check and display initial balances using common function
log ""
display_balances_hub
display_balances_connected_apt
log_and_echo ""

log ""
log "   Creating outflow intent on hub chain..."
log "   - Alice creates outflow intent on Chain 1 (hub chain)"
log "   - Alice locks 100000000 tokens on hub chain"
log "   - Alice wants 100000000 tokens on connected chain (Chain 2)"
log "   - Using intent_id: $INTENT_ID"

# Get APT metadata addresses for both chains using helper function
log "   - Getting APT metadata addresses..."

# Get APT metadata on Chain 1 (hub)
log "     Getting APT metadata on Chain 1..."
APT_METADATA_CHAIN1=$(extract_apt_metadata "alice-chain1" "$CHAIN1_ADDRESS" "$ALICE_CHAIN1_ADDRESS" "1" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 1: $APT_METADATA_CHAIN1"
OFFERED_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"

# Get APT metadata on Chain 2 (connected chain)
log "     Getting APT metadata on Chain 2..."
APT_METADATA_CHAIN2=$(extract_apt_metadata "alice-chain2" "$CHAIN2_ADDRESS" "$ALICE_CHAIN2_ADDRESS" "2" "$LOG_FILE")
log "     ✅ Got APT metadata on Chain 2: $APT_METADATA_CHAIN2"
DESIRED_FA_METADATA_CHAIN2="$APT_METADATA_CHAIN2"

# Create outflow request intent on Chain 1 using fa_intent_outflow module
# NOTE: Outflow intents must be reserved. This requires:
# 1. Off-chain negotiation with solver (Bob)
# 2. Solver signs IntentToSign structure (BCS-encoded)
# 3. Pass solver address and signature to create_outflow_request_intent_entry
#
# For outflow intents:
# - offered tokens are on hub chain (Chain 1) - these tokens are locked
# - desired tokens are on connected chain (Chain 2)
#
log "   - Creating outflow request intent on Chain 1..."
log "     Offered FA metadata (hub): $OFFERED_FA_METADATA_CHAIN1"
log "     Desired FA metadata (connected): $DESIRED_FA_METADATA_CHAIN2"
log "     Solver (Bob) address: $BOB_CHAIN1_ADDRESS"
log "     Requester address on connected chain: $ALICE_CHAIN2_ADDRESS"
log "     Generating solver signature..."

# Generate solver signature using helper function
# For outflow intents: offered tokens are on hub chain (chain 1), desired tokens are on connected chain (2)
OFFERED_AMOUNT="100000000"
OFFERED_CHAIN_ID=1  # Hub chain where tokens are locked
DESIRED_AMOUNT="100000000"
DESIRED_CHAIN_ID=$CONNECTED_CHAIN_ID  # Connected chain where Alice wants tokens (2 for Move VM)
SOLVER_SIGNATURE=$(generate_solver_signature \
    "bob-chain1" \
    "$CHAIN1_ADDRESS" \
    "$OFFERED_FA_METADATA_CHAIN1" \
    "$OFFERED_AMOUNT" \
    "$OFFERED_CHAIN_ID" \
    "$DESIRED_FA_METADATA_CHAIN2" \
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

# Remove 0x prefix from signature and verifier public key for hex format
SOLVER_SIGNATURE_HEX="${SOLVER_SIGNATURE#0x}"
VERIFIER_PUBLIC_KEY_HEX="${VERIFIER_PUBLIC_KEY#0x}"
HUB_CHAIN_ID=1

# Call create_outflow_request_intent_entry
# Parameters: offered_metadata, offered_amount, offered_chain_id, desired_metadata, desired_amount,
#             desired_chain_id, expiry_time, intent_id, requester_address_connected_chain,
#             verifier_public_key, solver, solver_signature
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_outflow::create_outflow_request_intent_entry" \
    --args "address:${OFFERED_FA_METADATA_CHAIN1}" "u64:${OFFERED_AMOUNT}" "u64:${HUB_CHAIN_ID}" "address:${DESIRED_FA_METADATA_CHAIN2}" "u64:${DESIRED_AMOUNT}" "u64:${CONNECTED_CHAIN_ID}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" "address:${ALICE_CHAIN2_ADDRESS}" "hex:${VERIFIER_PUBLIC_KEY_HEX}" "address:${BOB_CHAIN1_ADDRESS}" "hex:${SOLVER_SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Outflow intent created on Chain 1!"

    # Verify intent was stored on-chain by checking Alice's latest transaction
    sleep 2
    log "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent") or .type | contains("OracleLimitOrderEvent")) | .data.intent_address' | head -n 1)

    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub outflow intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Outflow intent created"
    else
        log_and_echo "     ❌ ERROR: Could not verify hub outflow intent address"
        exit 1
    fi
else
    log_and_echo "     ❌ Outflow intent creation failed on Chain 1!"
    log_and_echo "   Log file contents:"
    cat "$LOG_FILE"
    exit 1
fi

log ""
log "🎉 HUB CHAIN OUTFLOW INTENT CREATION COMPLETE!"
log "==============================================="
log ""
log "✅ Step completed successfully:"
log "   1. Outflow intent created on Chain 1 (hub chain)"
log "   2. Tokens locked on hub chain"
log ""
log "📋 Intent Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Outflow Intent: $HUB_INTENT_ADDRESS"
fi
log "   Requester address on connected chain: $ALICE_CHAIN2_ADDRESS"

# Export values for use by other scripts
save_intent_info "$INTENT_ID" "$HUB_INTENT_ADDRESS"

# Check final balances using common function
display_balances_hub
display_balances_connected_apt
log_and_echo ""

