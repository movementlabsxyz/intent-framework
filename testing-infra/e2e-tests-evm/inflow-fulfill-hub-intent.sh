#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root and logging
setup_project_root
setup_logging "fulfill-hub-intent"
cd "$PROJECT_ROOT"

# ============================================================================
# SECTION 1: LOAD DEPENDENCIES
# ============================================================================
if ! load_intent_info "INTENT_ID,HUB_INTENT_ADDRESS"; then
    exit 1
fi

# ============================================================================
# SECTION 2: GET ADDRESSES AND CONFIGURATION
# ============================================================================
CHAIN1_ADDRESS=$(get_profile_address "intent-account-chain1")
SOLVER_CHAIN1_ADDRESS=$(get_profile_address "solver-chain1")

log ""
log "📋 Chain Information:"
log "   Hub Chain Module Address (Chain 1):     $CHAIN1_ADDRESS"
log "   Solver Chain 1 (hub):       $SOLVER_CHAIN1_ADDRESS"
log "   Intent ID:               $INTENT_ID"
log "   Hub Request Intent Address: $HUB_INTENT_ADDRESS"

# ============================================================================
# SECTION 3: DISPLAY INITIAL STATE
# ============================================================================
log ""
display_balances_hub
display_balances_connected_evm
log_and_echo ""

# ============================================================================
# SECTION 4: EXECUTE MAIN OPERATION
# ============================================================================
log ""
log "   Fulfilling request intent on hub chain..."
log "   - Solver (Solver) sees request intent with ID: $INTENT_ID"
log "   - Solver (Solver) provides 1000 USDxyz on hub chain to fulfill the request intent"

INTENT_OBJECT_ADDRESS="$HUB_INTENT_ADDRESS"

if [ -z "$INTENT_OBJECT_ADDRESS" ] || [ "$INTENT_OBJECT_ADDRESS" = "null" ]; then
    log_and_echo "❌ ERROR: Could not get intent object address"
    exit 1
fi

log "   - Fulfilling intent at: $INTENT_OBJECT_ADDRESS"

# Fulfill with 1000 USDxyz (8 decimals = 100000000000)
aptos move run --profile solver-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_inflow::fulfill_inflow_request_intent" \
    --args "address:$INTENT_OBJECT_ADDRESS" "u64:100000000000" >> "$LOG_FILE" 2>&1

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
if [ $? -eq 0 ]; then
    log "     ✅ Solver (Solver) successfully fulfilled the request intent!"
    log_and_echo "✅ Request intent fulfilled"
else
    log_and_echo "❌ Request intent fulfillment failed!"
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
display_balances_hub
display_balances_connected_evm
log_and_echo ""

log ""
log "🎉 INFLOW - HUB CHAIN INTENT FULFILLMENT COMPLETE!"
log "=================================================="
log ""
log "✅ Step completed successfully:"
log "   1. Request intent fulfilled on Chain 1 by solver (Solver)"
log ""
log "📋 Request Intent Details:"
log "   Intent ID: $INTENT_ID"
log "   Chain 1 Hub Request Intent: $HUB_INTENT_ADDRESS"

