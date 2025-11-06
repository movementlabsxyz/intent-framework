#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-hub-intent"
cd "$PROJECT_ROOT"

log "======================================"
log "🎯 HUB CHAIN INTENT - CREATE & FULFILL"
log "======================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""
log "This script handles hub chain intent operations:"
log "  1. [HUB CHAIN] User creates intent requesting tokens"
log "  2. [HUB CHAIN] Solver fulfills intent on hub chain"
log ""
log "Note: Escrow creation on connected chain should be done separately"
log "      using: ./testing-infra/e2e-tests-apt/submit-escrow.sh"

# Generate a random intent_id that will be used for both hub and escrow
INTENT_ID="0x$(openssl rand -hex 32)"

# Get addresses
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

# Get Alice and Bob addresses
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
ALICE_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Connected Chain (Chain 2): $CHAIN2_ADDRESS"
log "   Alice Chain 1 (hub):     $ALICE_CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Alice Chain 2 (connected): $ALICE_CHAIN2_ADDRESS"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

log ""
log "🔑 Configuration:"
log "   Intent ID: $INTENT_ID"
log "   Expiry time: $EXPIRY_TIME"

# Check and display initial balances using common function
log ""
display_balances

log ""
log "📝 STEP 1: [HUB CHAIN] Alice creates intent requesting tokens"
log "================================================="
log "   User creates intent on hub chain requesting tokens from solver"
log "   - Alice creates intent on Chain 1 (hub chain)"
log "   - Intent requests 100000000 tokens to be provided by solver"
log "   - Using intent_id: $INTENT_ID"

# Get APT metadata addresses for both chains using helper function
log "   - Getting APT metadata addresses..."

# Get APT metadata on Chain 1
log "     Getting APT metadata on Chain 1..."
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::test_fa_helper::get_apt_metadata_address" \
    >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    sleep 2
    APT_METADATA_CHAIN1=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("APTMetadataAddressEvent")) | .data.metadata' | head -n 1)
    if [ -n "$APT_METADATA_CHAIN1" ] && [ "$APT_METADATA_CHAIN1" != "null" ]; then
        log "     ✅ Got APT metadata on Chain 1: $APT_METADATA_CHAIN1"
        SOURCE_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"
        DESIRED_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"
    else
        log_and_echo "     ❌ Failed to extract APT metadata from Chain 1 transaction"
        exit 1
    fi
else
    log_and_echo "     ❌ Failed to get APT metadata on Chain 1"
    exit 1
fi

# Get APT metadata on Chain 2
log "     Getting APT metadata on Chain 2..."
aptos move run --profile alice-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::test_fa_helper::get_apt_metadata_address" \
    >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    sleep 2
    APT_METADATA_CHAIN2=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("APTMetadataAddressEvent")) | .data.metadata' | head -n 1)
    if [ -n "$APT_METADATA_CHAIN2" ] && [ "$APT_METADATA_CHAIN2" != "null" ]; then
        log "     ✅ Got APT metadata on Chain 2: $APT_METADATA_CHAIN2"
        SOURCE_FA_METADATA_CHAIN2="$APT_METADATA_CHAIN2"
    else
        log_and_echo "     ❌ Failed to extract APT metadata from Chain 2 transaction"
        exit 1
    fi
else
    log_and_echo "     ❌ Failed to get APT metadata on Chain 2"
    exit 1
fi

# Create cross-chain request intent on Chain 1 using fa_intent module
log "   - Creating cross-chain request intent on Chain 1..."
log "     Source FA metadata: $SOURCE_FA_METADATA_CHAIN1"
log "     Desired FA metadata: $DESIRED_FA_METADATA_CHAIN1"
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_cross_chain::create_cross_chain_request_intent_entry" \
    --args "address:${SOURCE_FA_METADATA_CHAIN1}" "address:${DESIRED_FA_METADATA_CHAIN1}" "u64:100000000" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" >> "$LOG_FILE" 2>&1

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
        # Export for use in fulfillment step
        export HUB_INTENT_ADDRESS
    else
        log_and_echo "     ❌ ERROR: Could not verify hub intent address"
        exit 1
    fi
else
    log_and_echo "     ❌ Intent creation failed on Chain 1!"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

log ""
log "📝 STEP 2: [HUB CHAIN] Bob fulfills intent on hub chain"
log "================================================="
log "   Solver monitors escrow event on connected chain and fulfills intent on hub chain"
log "   - Solver sees escrow event on connected chain"
log "   - Bob sees intent with ID: $INTENT_ID"
log "   - Bob provides 100000000 tokens on hub chain to fulfill the intent"

# Get the intent object address from Step 1
INTENT_OBJECT_ADDRESS="$HUB_INTENT_ADDRESS"

if [ -n "$INTENT_OBJECT_ADDRESS" ] && [ "$INTENT_OBJECT_ADDRESS" != "null" ]; then
    log "   - Fulfilling intent at: $INTENT_OBJECT_ADDRESS"
    
    # Bob fulfills the intent by providing tokens
    aptos move run --profile bob-chain1 --assume-yes \
        --function-id "0x${CHAIN1_ADDRESS}::fa_intent_cross_chain::fulfill_cross_chain_request_intent" \
        --args "address:$INTENT_OBJECT_ADDRESS" "u64:100000000" >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        log "     ✅ Bob successfully fulfilled the intent!"
        log_and_echo "✅ Intent fulfilled"
    else
        log_and_echo "     ❌ Intent fulfillment failed!"
        exit 1
    fi
else
    log_and_echo "     ❌ ERROR: Could not get intent object address"
    exit 1
fi

log ""
log "🎉 HUB CHAIN INTENT OPERATIONS COMPLETE!"
log "========================================"
log ""
log "✅ Steps completed successfully:"
log "   1. Intent created on Chain 1 (hub chain)"
log "   2. Intent fulfilled on Chain 1 by Bob"
log ""
log "📋 Intent Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Intent: $HUB_INTENT_ADDRESS"
fi

# Export values for use by other scripts (write to a temp file for easy sourcing)
INTENT_INFO_FILE="${PROJECT_ROOT}/tmp/intent-info.env"
mkdir -p "$(dirname "$INTENT_INFO_FILE")"
echo "INTENT_ID=$INTENT_ID" > "$INTENT_INFO_FILE"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    echo "HUB_INTENT_ADDRESS=$HUB_INTENT_ADDRESS" >> "$INTENT_INFO_FILE"
fi
log "   📝 Intent info saved to: $INTENT_INFO_FILE"

# Check final balances using common function
display_balances

log ""
log "🔍 Next Steps:"
log "   To create escrow on connected chain, run:"
log "   INTENT_ID=$INTENT_ID ./testing-infra/e2e-tests-apt/submit-escrow.sh"
log ""
log "✨ Script completed!"

