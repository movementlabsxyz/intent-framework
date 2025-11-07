#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_apt.sh"

# Setup project root and logging
setup_project_root
setup_logging "fulfill-hub-intent"
cd "$PROJECT_ROOT"


# Load INTENT_ID and HUB_INTENT_ADDRESS from info file
if ! load_intent_info "INTENT_ID,HUB_INTENT_ADDRESS"; then
    exit 1
fi

# Get addresses
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Intent ID:               $INTENT_ID"
log "   Hub Intent Address:      $HUB_INTENT_ADDRESS"

log ""
log "   Fulfilling intent on hub chain..."
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


