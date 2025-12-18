#!/bin/bash

# Wait for escrow claim script for EVM E2E tests
# Polls for escrow claim status and exits with error if not claimed within timeout

set -e

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_evm.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root
setup_project_root

# Load chain info and intent info
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true

# Load INTENT_ID - this will exit if missing
log "   Loading intent info..."
load_intent_info "INTENT_ID"
log "   ✅ load_intent_info completed, INTENT_ID=${INTENT_ID:0:20}..."

# Verify INTENT_ID was actually loaded (defensive check)
if [ -z "$INTENT_ID" ]; then
    log_and_echo "❌ PANIC: INTENT_ID is empty after load_intent_info"
    log_and_echo "   This should not happen - load_intent_info should have exited"
    log_and_echo "   Checking intent-info.env file..."
    if [ -f "$PROJECT_ROOT/.tmp/intent-info.env" ]; then
        log_and_echo "   File exists, contents:"
        cat "$PROJECT_ROOT/.tmp/intent-info.env" | sed 's/^/      /'
    else
        log_and_echo "   File does not exist: $PROJECT_ROOT/.tmp/intent-info.env"
    fi
    display_service_logs "INTENT_ID empty after load"
    exit 1
fi

ESCROW_ADDRESS="${ESCROW_CONTRACT_ADDRESS:-}"
INTENT_ID_EVM="${INTENT_ID_EVM:-}"

# Convert INTENT_ID to EVM format if INTENT_ID_EVM is not set
if [ -z "$INTENT_ID_EVM" ] && [ -n "$INTENT_ID" ]; then
    INTENT_ID_EVM=$(convert_intent_id_to_evm "$INTENT_ID")
fi

if [ -z "$ESCROW_ADDRESS" ] || [ -z "$INTENT_ID_EVM" ]; then
    log_and_echo "❌ PANIC: Missing required variables for escrow claim check"
    log_and_echo "   ESCROW_ADDRESS: ${ESCROW_ADDRESS:-not set}"
    log_and_echo "   INTENT_ID_EVM: ${INTENT_ID_EVM:-not set}"
    log_and_echo "   INTENT_ID: ${INTENT_ID:-not set}"
    display_service_logs "Missing variables for escrow claim check"
    exit 1
fi

log_and_echo "⏳ Waiting for solver to claim escrow..."
log_and_echo "   Escrow: $ESCROW_ADDRESS"
log_and_echo "   Intent ID (EVM): $INTENT_ID_EVM"

# Poll for escrow claim (max 30 seconds, every 2 seconds)
MAX_ATTEMPTS=15
ATTEMPT=1
ESCROW_CLAIMED=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    CLAIM_STATUS=$(is_escrow_claimed "$ESCROW_ADDRESS" "$INTENT_ID_EVM" 2>/dev/null || echo "false")
    if [ "$CLAIM_STATUS" = "true" ]; then
        log_and_echo "   ✅ Escrow claimed!"
        ESCROW_CLAIMED=true
        break
    fi
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep 2
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$ESCROW_CLAIMED" = "false" ]; then
    log_and_echo "❌ PANIC: Escrow not claimed after ${MAX_ATTEMPTS} attempts (${MAX_ATTEMPTS}s)"
    display_service_logs "Escrow claim timeout"
    exit 1
fi

