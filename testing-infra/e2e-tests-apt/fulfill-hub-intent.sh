#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "fulfill-hub-intent"
cd "$PROJECT_ROOT"

log "======================================"
log "🎯 HUB CHAIN INTENT - FULFILL"
log "======================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""
log "This script fulfills intent on hub chain:"
log "  [HUB CHAIN] Solver fulfills intent on hub chain"
log ""
log "Note: Intent should be created first using:"
log "      ./testing-infra/e2e-tests-apt/submit-hub-intent.sh"
log ""
log "Usage: ./testing-infra/e2e-tests-apt/fulfill-hub-intent.sh"
log "   (INTENT_ID and HUB_INTENT_ADDRESS will be loaded from tmp/intent-info.env)"

# Load INTENT_ID and HUB_INTENT_ADDRESS from info file
INTENT_INFO_FILE="${PROJECT_ROOT}/tmp/intent-info.env"
if [ -f "$INTENT_INFO_FILE" ]; then
    source "$INTENT_INFO_FILE"
    log "   ✅ Loaded INTENT_ID and HUB_INTENT_ADDRESS from $INTENT_INFO_FILE"
else
    log_and_echo "❌ ERROR: intent-info.env not found at $INTENT_INFO_FILE"
    log_and_echo "   Run submit-hub-intent.sh first, or provide INTENT_ID=<id> and HUB_INTENT_ADDRESS=<address>"
    exit 1
fi

if [ -z "$INTENT_ID" ] || [ -z "$HUB_INTENT_ADDRESS" ]; then
    log_and_echo "❌ ERROR: INTENT_ID or HUB_INTENT_ADDRESS not found in intent-info.env"
    log_and_echo "   Run submit-hub-intent.sh first"
    exit 1
fi

# Get addresses
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Intent ID:               $INTENT_ID"
log "   Hub Intent Address:      $HUB_INTENT_ADDRESS"

log ""
log "📝 STEP 1: [HUB CHAIN] Bob fulfills intent on hub chain"
log "================================================="
log "   Solver monitors escrow event and fulfills intent on hub chain"
log "   - Bob sees intent with ID: $INTENT_ID"
log "   - Bob provides 100000000 tokens on hub chain to fulfill the intent"

# Get the intent object address
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
log "🎉 HUB CHAIN INTENT FULFILLMENT COMPLETE!"
log "=========================================="
log ""
log "✅ Step completed successfully:"
log "   1. Intent fulfilled on Chain 1 by Bob"
log ""
log "📋 Intent Details:"
log "   Intent ID: $INTENT_ID"
log "   Chain 1 Hub Intent: $HUB_INTENT_ADDRESS"

# Check final balances using common function
display_balances

log ""
log "✨ Script completed!"

