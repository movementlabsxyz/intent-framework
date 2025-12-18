#!/bin/bash

# Wait for escrow claim script for MVM E2E tests
# Checks if escrow object was deleted (claimed) by querying the REST API
# When an escrow is claimed, the intent object is deleted from the chain

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

setup_project_root

# Load chain info and intent info
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true

# Load ESCROW_ADDRESS
if [ ! -f "$PROJECT_ROOT/.tmp/intent-info.env" ]; then
    log_and_echo "❌ PANIC: intent-info.env not found"
    exit 1
fi
source "$PROJECT_ROOT/.tmp/intent-info.env"

ESCROW_ADDRESS="${CHAIN2_ESCROW_ADDRESS:-}"

if [ -z "$ESCROW_ADDRESS" ]; then
    log_and_echo "❌ PANIC: CHAIN2_ESCROW_ADDRESS not set in intent-info.env"
    exit 1
fi

log_and_echo "⏳ Waiting for solver to claim escrow..."
log "   Escrow: $ESCROW_ADDRESS"

# Poll for escrow claim (max 30 seconds, every 2 seconds)
MAX_ATTEMPTS=15
ATTEMPT=1
ESCROW_CLAIMED=false

# Strip 0x prefix if present for API call
ESCROW_ADDRESS_CLEAN=$(printf '%s' "$ESCROW_ADDRESS" | sed 's/^0x//')

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    # Check if escrow object still exists - if deleted, returns 404 or error
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8082/v1/accounts/${ESCROW_ADDRESS_CLEAN}/resources" 2>/dev/null || printf "000")
    
    if [ "$HTTP_STATUS" = "404" ] || [ "$HTTP_STATUS" = "400" ]; then
        log_and_echo "   ✅ Escrow claimed! (object deleted, HTTP $HTTP_STATUS)"
        ESCROW_CLAIMED=true
        break
    fi
    
    # Also check if Intent resource is missing from the resources
    INTENT_RESOURCE=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ESCROW_ADDRESS_CLEAN}/resources" 2>/dev/null | \
        jq -r '.[] | select(.type | contains("Intent")) | .type' 2>/dev/null || printf "")
    
    if [ -z "$INTENT_RESOURCE" ]; then
        log_and_echo "   ✅ Escrow claimed! (Intent resource not found)"
        ESCROW_CLAIMED=true
        break
    fi
    
    log "   Attempt $ATTEMPT/$MAX_ATTEMPTS: Escrow still exists, waiting..."
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep 2
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$ESCROW_CLAIMED" = "false" ]; then
    log_and_echo "❌ PANIC: Escrow not claimed after ${MAX_ATTEMPTS} attempts ($((MAX_ATTEMPTS * 2))s)"
    log_and_echo "   Escrow object still exists at: $ESCROW_ADDRESS"
    display_service_logs "Escrow claim timeout"
    exit 1
fi

log_and_echo "✅ Escrow claim verified!"

