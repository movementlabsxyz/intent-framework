#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root and logging
setup_project_root
setup_logging "verifier_and_escrow_release"
cd "$PROJECT_ROOT"

log ""
log "🔍 CROSS-CHAIN VERIFIER - ESCROW RELEASE MONITORING"
log "===================================================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

log "This script will:"
log "  1. Check verifier status and monitored events"
log "  2. Monitor for escrow approvals"
log "  3. Automatically release escrows when approvals are available"
log ""

# ============================================================================
# SECTION 1: CHECK VERIFIER STATUS
# ============================================================================
log ""
log "   - Checking if verifier is running..."
if ! curl -s "http://127.0.0.1:3333/health" > /dev/null 2>&1; then
    log_and_echo "❌ ERROR: Verifier is not running"
    log_and_echo "   Please start the verifier service first"
    log_and_echo "   The verifier should be started in run-tests.sh before this script"
    exit 1
fi
log "   ✅ Verifier is running"

# Set VERIFIER_LOG if not already set (from start_verifier)
if [ -z "$VERIFIER_LOG" ]; then
    VERIFIER_LOG="$LOG_DIR/verifier.log"
    if [ ! -f "$VERIFIER_LOG" ]; then
        # Try to find verifier log in common locations
        if [ -f "$PROJECT_ROOT/tmp/intent-framework-logs/verifier.log" ]; then
            VERIFIER_LOG="$PROJECT_ROOT/tmp/intent-framework-logs/verifier.log"
        fi
    fi
fi

# ============================================================================
# SECTION 1.5: CAPTURE INITIAL BALANCES (for final validation)
# ============================================================================
log ""
log "📊 Capturing initial balances for validation..."
# Note: Alice's balance on Chain 1 is validated in inflow-fulfill-hub-intent.sh (hub intent fulfillment)
# We only need to check Bob's balance on Chain 2 (escrow release)

BOB_CHAIN2_ADDRESS_INIT=$(get_profile_address "bob-chain2")
BOB_CHAIN2_BALANCE_INIT=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' 2>/dev/null || echo "0")

# Remove commas
BOB_CHAIN2_BALANCE_INIT=$(echo "$BOB_CHAIN2_BALANCE_INIT" | tr -d ',')

log "   Initial balances:"
log "      Bob Chain 2: $BOB_CHAIN2_BALANCE_INIT Octas"

log ""
log "📋 Verifier Status:"
log "========================================"

VERIFIER_EVENTS=$(curl -s "http://127.0.0.1:3333/events")

# Check if verifier has intent events
INTENT_COUNT=$(echo "$VERIFIER_EVENTS" | jq -r '.data.intent_events | length' 2>/dev/null || echo "0")
ESCROW_COUNT=$(echo "$VERIFIER_EVENTS" | jq -r '.data.escrow_events | length' 2>/dev/null || echo "0")
FULFILLMENT_COUNT=$(echo "$VERIFIER_EVENTS" | jq -r '.data.fulfillment_events | length' 2>/dev/null || echo "0")

if [ "$INTENT_COUNT" = "0" ] && [ "$ESCROW_COUNT" = "0" ] && [ "$FULFILLMENT_COUNT" = "0" ]; then
    log "   ⚠️  No events monitored yet"
    log "   Verifier is running and waiting for events"
else
    if [ "$INTENT_COUNT" != "0" ]; then
        log "   ✅ Verifier has monitored $INTENT_COUNT intent events:"
        log "$VERIFIER_EVENTS" | jq -r '.data.intent_events[] | 
            "     chain: \(.chain)",
            "     intent_id: \(.intent_id)",
            "     issuer: \(.issuer)",
            "     offered_metadata: \(.offered_metadata)",
            "     offered_amount: \(.offered_amount)",
            "     desired_metadata: \(.desired_metadata)",
            "     desired_amount: \(.desired_amount)",
            "     expiry_time: \(.expiry_time)",
            "     revocable: \(.revocable)",
            "     timestamp: \(.timestamp)",
            ""' 2>/dev/null || log "     (Unable to parse events)"
    fi
    
    if [ "$ESCROW_COUNT" != "0" ]; then
        log "   ✅ Verifier has monitored $ESCROW_COUNT escrow events:"
        log "$VERIFIER_EVENTS" | jq -r '.data.escrow_events[] | 
            "     chain: \(.chain)",
            "     escrow_id: \(.escrow_id)",
            "     intent_id: \(.intent_id)",
            "     issuer: \(.issuer)",
            "     offered_metadata: \(.offered_metadata)",
            "     offered_amount: \(.offered_amount)",
            "     desired_metadata: \(.desired_metadata)",
            "     desired_amount: \(.desired_amount)",
            "     expiry_time: \(.expiry_time)",
            "     revocable: \(.revocable)",
            "     timestamp: \(.timestamp)",
            ""' 2>/dev/null || log "     (Unable to parse events)"
    fi
    
    if [ "$FULFILLMENT_COUNT" != "0" ]; then
        log "   ✅ Verifier has monitored $FULFILLMENT_COUNT fulfillment events:"
        log "$VERIFIER_EVENTS" | jq -r '.data.fulfillment_events[] | 
            "     chain: \(.chain)",
            "     intent_id: \(.intent_id)",
            "     intent_address: \(.intent_address)",
            "     solver: \(.solver)",
            "     provided_metadata: \(.provided_metadata)",
            "     provided_amount: \(.provided_amount)",
            "     timestamp: \(.timestamp)",
            ""' 2>/dev/null || log "     (Unable to parse events)"
    fi
fi

# Check for rejected intents in the logs
log ""
log "📋 Rejected Intents:"
log "========================================"
REJECTED_COUNT=$(grep -c "SECURITY: Rejecting" "$VERIFIER_LOG" 2>/dev/null || echo "0")
# Trim any whitespace and ensure it's a number
REJECTED_COUNT=$(echo "$REJECTED_COUNT" | tr -d ' \n\t' | head -1)
REJECTED_COUNT=${REJECTED_COUNT:-0}

# Use numeric comparison: only exit if count > 0
if [ "$REJECTED_COUNT" -eq 0 ] 2>/dev/null; then
    log_and_echo "✅ No intents rejected"
else
    log_and_echo "   ❌ ERROR: Found $REJECTED_COUNT rejected intents (showing unique chain+intent combinations only):"
    # Use associative array to track unique chain+intent combinations
    declare -A seen_keys
    
    grep -n "SECURITY: Rejecting" "$VERIFIER_LOG" 2>/dev/null | while IFS= read -r line_with_num; do
        LINE_NUM=$(echo "$line_with_num" | cut -d: -f1)
        REJECTION_LINE=$(echo "$line_with_num" | cut -d: -f2-)
        
        # Extract details from log line
        INTENT_INFO=$(echo "$REJECTION_LINE" | grep -oE "intent [0-9a-fx]+" | sed 's/intent //')
        CREATOR_INFO=$(echo "$REJECTION_LINE" | grep -oE "from [0-9a-fx]+" | sed 's/from //')
        REASON=$(echo "$REJECTION_LINE" | sed 's/.*SECURITY: //' | sed 's/ - NOT safe for escrow.*/ - NOT safe for escrow/' || echo "Revocable intent")
        
        # Determine which chain by checking the line before the rejection
        PREV_LINE=$(sed -n "$((LINE_NUM-1))p" "$VERIFIER_LOG")
        if echo "$PREV_LINE" | grep -q "Received intent event"; then
            CHAIN="Chain 1 (Hub)"
        elif echo "$PREV_LINE" | grep -q "Received escrow event"; then
            CHAIN="Chain 2 (Connected)"
        else
            CHAIN="Unknown Chain"
        fi
        
        # Create unique key combining chain and intent ID for deduplication
        if [ -n "$INTENT_INFO" ]; then
            KEY="${CHAIN}:${INTENT_INFO}"
            if [ -z "${seen_keys[$KEY]}" ]; then
                seen_keys[$KEY]=1
                log "     ❌ Chain: $CHAIN"
                log "        Intent: $INTENT_INFO"
                [ -n "$CREATOR_INFO" ] && log "        Creator: $CREATOR_INFO"
                [ -n "$REASON" ] && log "        Reason: $REASON"
                log ""
            fi
        fi
    done
    
    # Panic if there are rejected intents
    log ""
    log_and_echo "   ❌ FATAL: Rejected intents detected. Exiting..."
    exit 1
fi

log ""
log "🔍 Verifier is now monitoring:"
log "   - Chain 1 (hub) at http://127.0.0.1:8080"
log "   - Chain 2 (connected) at http://127.0.0.1:8082"
log "   - API available at http://127.0.0.1:3333"

log ""
log "🔓 Starting automatic escrow release monitoring..."
log "=================================================="

# Get Chain 2 deployer address for function calls
CHAIN2_DEPLOY_ADDRESS=$(get_profile_address "intent-account-chain2")
if [ -z "$CHAIN2_DEPLOY_ADDRESS" ] || [ "$CHAIN2_DEPLOY_ADDRESS" = "null" ]; then
    log_and_echo "   ❌ ERROR: Could not find Chain 2 deployer address"
    log_and_echo "      Automatic escrow release requires a valid deployer address"
    exit 1
else
    log "   ✅ Automatic escrow release enabled"
    log "      Chain 2 deployer: 0x$CHAIN2_DEPLOY_ADDRESS"
    
    # Track released escrows to avoid duplicate attempts
    RELEASED_ESCROWS=""
    
    # Function to check for new approvals and release escrows
    check_and_release_escrows() {
        APPROVALS_RESPONSE=$(curl -s "http://127.0.0.1:3333/approvals")
        
        if [ $? -ne 0 ]; then
            return 1
        fi
        
        APPROVALS_SUCCESS=$(echo "$APPROVALS_RESPONSE" | jq -r '.success' 2>/dev/null)
        if [ "$APPROVALS_SUCCESS" != "true" ]; then
            return 1
        fi
        
        # Extract approvals array
        APPROVALS_COUNT=$(echo "$APPROVALS_RESPONSE" | jq -r '.data | length' 2>/dev/null || echo "0")
        
        if [ "$APPROVALS_COUNT" = "0" ]; then
            return 0
        fi
        
        # Process each approval
        for i in $(seq 0 $((APPROVALS_COUNT - 1))); do
            ESCROW_ID=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].escrow_id" 2>/dev/null | tr -d '\n\r\t ')
            INTENT_ID=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].intent_id" 2>/dev/null | tr -d '\n\r\t ')
            SIGNATURE_BASE64=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].signature" 2>/dev/null | tr -d '\n\r\t ')
            
            if [ -z "$ESCROW_ID" ] || [ "$ESCROW_ID" = "null" ]; then
                continue
            fi
            
            # Verify escrow_id is a valid Move VM object address format
            # Move VM addresses: 0x followed by 1-64 hex characters (3-66 chars total)
            # Object addresses can be shorter than 64 hex chars (leading zeros may be omitted)
            if [ ${#ESCROW_ID} -lt 3 ] || [ ${#ESCROW_ID} -gt 66 ] || ! echo "$ESCROW_ID" | grep -qE '^0x[0-9a-fA-F]{1,64}$'; then
                log_and_echo "   ❌ ERROR: escrow_id from approval is invalid: $ESCROW_ID"
                log_and_echo "   ❌ Expected format: 0x followed by 1-64 hex characters (3-66 chars total)"
                log_and_echo "   ❌ This indicates a configuration error in the verifier"
                exit 1
            fi
            
            # Verify escrow exists in events (handles race condition where verifier hasn't polled yet)
            EVENTS_RESPONSE=""
            MAX_RETRIES=5
            RETRY_DELAY=3
            ESCROW_FOUND=false
            
            for retry in $(seq 1 $MAX_RETRIES); do
                # Get escrow events and verify the escrow_id exists
                EVENTS_RESPONSE=$(curl -s "http://127.0.0.1:3333/events")
                ESCROW_EXISTS=$(echo "$EVENTS_RESPONSE" | jq -r ".data.escrow_events[] | select(.escrow_id == \"$ESCROW_ID\") | .escrow_id" 2>/dev/null | head -1)
                
                if [ -n "$ESCROW_EXISTS" ] && [ "$ESCROW_EXISTS" != "null" ]; then
                    log "   ✅ Verified escrow object address exists in events: $ESCROW_ID (attempt $retry/$MAX_RETRIES)"
                    ESCROW_FOUND=true
                    break
                else
                    # Escrow not found in events yet, wait and retry
                    if [ $retry -lt $MAX_RETRIES ]; then
                        log "   ⏳ Escrow $ESCROW_ID not found in events yet, waiting ${RETRY_DELAY}s before retry ($retry/$MAX_RETRIES)..."
                        sleep $RETRY_DELAY
                    fi
                fi
            done
            
            if [ "$ESCROW_FOUND" != "true" ]; then
                log_and_echo "   ❌ ERROR: Escrow object address $ESCROW_ID not found in verifier events after $MAX_RETRIES attempts"
                log_and_echo "   ❌ This indicates the verifier may not have polled the escrow event yet, or escrow was not created"
                log_and_echo "   ❌ Cannot continue without verified escrow object address"
                log_and_echo "   Verifier log:"
                log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
                cat "$VERIFIER_LOG"
                log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
                exit 1
            fi
            
            # Skip if already released
            if [[ "$RELEASED_ESCROWS" == *"$ESCROW_ID"* ]]; then
                continue
            fi
            
            log ""
            log "   📦 New approval found for escrow: $ESCROW_ID"
            log "   🔓 Releasing escrow..."
            
            # Get solver (Bob)'s balance before release (to verify funds were received)
            log "   - Getting solver (Bob)'s balance before release..."
            BOB_BALANCE_BEFORE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' 2>/dev/null || echo "0")
            if [ -z "$BOB_BALANCE_BEFORE" ] || [ "$BOB_BALANCE_BEFORE" = "null" ]; then
                BOB_BALANCE_BEFORE="0"
            fi
            # Remove commas from balance if present
            BOB_BALANCE_BEFORE=$(echo "$BOB_BALANCE_BEFORE" | tr -d ',')
            log "   - Solver (Bob)'s balance before release: $BOB_BALANCE_BEFORE Octas"
            
            # Decode base64 signature to hex
            SIGNATURE_HEX=$(echo "$SIGNATURE_BASE64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')
            
            if [ -z "$SIGNATURE_HEX" ]; then
                log "   ❌ Failed to decode signature"
                continue
            fi
            
            # Get desired_amount from escrow events (reuse if already fetched)
            if [ -z "$EVENTS_RESPONSE" ]; then
                EVENTS_RESPONSE=$(curl -s "http://127.0.0.1:3333/events")
            fi
            DESIRED_AMOUNT=$(echo "$EVENTS_RESPONSE" | jq -r ".data.escrow_events[] | select(.escrow_id == \"$ESCROW_ID\") | .desired_amount" 2>/dev/null | head -1)
            
            if [ -z "$DESIRED_AMOUNT" ] || [ "$DESIRED_AMOUNT" = "null" ] || [ "$DESIRED_AMOUNT" = "0" ]; then
                log "   ❌ ERROR: Could not determine desired_amount for escrow $ESCROW_ID"
                log "   ❌ Cannot complete escrow without knowing the required payment amount"
                exit 1
            fi
            
            PAYMENT_AMOUNT="$DESIRED_AMOUNT"
            log "   - Payment amount: $PAYMENT_AMOUNT (from escrow desired_amount)"
            
            # Submit escrow release transaction
            # Using bob-chain2 as solver (Bob) (needs to have APT for payment)
            # Note: Signature itself is the approval - no approval_value parameter needed
            
            aptos move run --profile bob-chain2 --assume-yes \
                --function-id "0x${CHAIN2_DEPLOY_ADDRESS}::intent_as_escrow_entry::complete_escrow_from_fa" \
                --args "address:${ESCROW_ID}" "u64:${PAYMENT_AMOUNT}" "hex:${SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1
            
            TX_EXIT_CODE=$?
            
            # Wait for transaction to be fully processed and finalized
            log "   - Waiting for escrow release transaction to be finalized..."
            sleep 10
            
            # Get solver (Bob)'s balance after release
            log "   - Getting solver (Bob)'s balance after release..."
            BOB_BALANCE_AFTER=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' 2>/dev/null || echo "0")
            if [ -z "$BOB_BALANCE_AFTER" ] || [ "$BOB_BALANCE_AFTER" = "null" ]; then
                BOB_BALANCE_AFTER="0"
            fi
            # Remove commas from balance if present
            BOB_BALANCE_AFTER=$(echo "$BOB_BALANCE_AFTER" | tr -d ',')
            log "   - Solver (Bob)'s balance after release: $BOB_BALANCE_AFTER Octas"
            
            # Calculate balance increase
            BALANCE_INCREASE=$((BOB_BALANCE_AFTER - BOB_BALANCE_BEFORE))
            
            # Expected amount: 1 APT (locked in escrow) minus gas fees
            # We expect at least 99% of the locked amount to be received (allowing for gas)
            EXPECTED_MIN_AMOUNT=99000000  # 99% of 100000000 (1 APT)
            
            if [ $TX_EXIT_CODE -eq 0 ]; then
                log "   ✅ Escrow release transaction succeeded!"
                
                # Verify solver (Bob) received the funds
                if [ "$BALANCE_INCREASE" -lt "$EXPECTED_MIN_AMOUNT" ]; then
                    log_and_echo "   ❌ ERROR: Solver (Bob) did not receive escrow funds!"
                    log_and_echo "      Balance increase: $BALANCE_INCREASE Octas"
                    log_and_echo "      Expected minimum: $EXPECTED_MIN_AMOUNT Octas (1 APT minus gas)"
                    log_and_echo "      Solver (Bob) balance before: $BOB_BALANCE_BEFORE Octas"
                    log_and_echo "      Solver (Bob) balance after: $BOB_BALANCE_AFTER Octas"
                    log_and_echo "      Escrow ID: $ESCROW_ID"
                    exit 1
                fi
                
                log "   ✅ Solver (Bob) received $BALANCE_INCREASE Octas (expected ~1 APT minus gas)"
                RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
            else
                # Check the log file for error messages
                ERROR_MSG=$(tail -100 "$LOG_FILE" | grep -oE "EOBJECT_DOES_NOT_EXIST|OBJECT_DOES_NOT_EXIST" || echo "")
                if [ -n "$ERROR_MSG" ]; then
                    # Escrow already released (object doesn't exist), verify solver (Bob) got the funds
                    log "   ℹ️  Escrow object no longer exists (may already be released)"
                    
                    # Verify solver (Bob) received the funds even though the object doesn't exist
                    if [ "$BALANCE_INCREASE" -lt "$EXPECTED_MIN_AMOUNT" ]; then
                        log_and_echo "   ❌ ERROR: Escrow object doesn't exist but solver (Bob) did NOT receive funds!"
                        log_and_echo "      Balance increase: $BALANCE_INCREASE Octas"
                        log_and_echo "      Expected minimum: $EXPECTED_MIN_AMOUNT Octas (1 APT minus gas)"
                        log_and_echo "      Solver (Bob) balance before: $BOB_BALANCE_BEFORE Octas"
                        log_and_echo "      Solver (Bob) balance after: $BOB_BALANCE_AFTER Octas"
                        log_and_echo "      Escrow ID: $ESCROW_ID"
                        log_and_echo "      This indicates the escrow was released but funds went to wrong address or were lost"
                        exit 1
                    fi
                    
                    log "   ✅ Verified: Solver (Bob) received $BALANCE_INCREASE Octas (escrow was already released)"
                    RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
                else
                    log "   ❌ Failed to release escrow"
                    log_and_echo "   ❌ ERROR: Escrow release failed and solver (Bob) did not receive funds"
                    log_and_echo "   Log file contents:"
                    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
                    cat "$LOG_FILE"
                    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
                    log_and_echo "      Balance increase: $BALANCE_INCREASE Octas"
                    log_and_echo "      Expected minimum: $EXPECTED_MIN_AMOUNT Octas"
                    exit 1
                fi
            fi
        done
    }
    
    # Poll for approvals a few times before script exits
    log "   - Checking for approvals (will check 10 times with 3 second intervals)..."
    for i in {1..10}; do
        sleep 3
        check_and_release_escrows
    done
    
    log "   ✅ Approval check complete"
    log ""
    
    # Check if any escrows were actually released
    if [ -z "$RELEASED_ESCROWS" ]; then
        log_and_echo "❌ ERROR: No escrows were released during the approval check period"
        log_and_echo "   This may indicate:"
        log_and_echo "      - The verifier has not yet generated an approval"
        log_and_echo "      - The hub intent fulfillment was not detected"
        log_and_echo "      - There is a timing issue"
        log ""
        log "🔍 Diagnostic Information:"
        log "========================================"
        log ""
        log "   Verifier approvals:"
        curl -s "http://127.0.0.1:3333/approvals" | jq '.' 2>/dev/null || log "      (Unable to query approvals)"
        log ""
        log "   Verifier events:"
        curl -s "http://127.0.0.1:3333/events" | jq '.data | {escrow_events: (.escrow_events | length), fulfillment_events: (.fulfillment_events | length), intent_events: (.intent_events | length)}' 2>/dev/null || log "      (Unable to query events)"
        log ""
        log "   Verifier log:"
        log "   + + + + + + + + + + + + + + + + + + + +"
        cat "$VERIFIER_LOG" 2>/dev/null || log "      (Log file not found)"
        log "   + + + + + + + + + + + + + + + + + + + +"
        exit 1
    else
        log_and_echo "   ✅ Released escrows: $RELEASED_ESCROWS"
    fi
    
    log ""
    log "   ℹ️  The verifier will continue monitoring in the background"
    log "      To manually check and release escrows, use:"
    log "      curl -s http://127.0.0.1:3333/approvals | jq"
fi

# ============================================================================
# SECTION 5: VERIFY RESULTS
# ============================================================================
# Verification is done inline during escrow release operations

# ============================================================================
# SECTION 6: FINAL BALANCE VALIDATION
# ============================================================================
log ""
log "🔍 Validating final balances after inflow flow..."
log "================================================"
log "   - Waiting for transactions to be fully processed..."
sleep 10

# Get current balances
# Note: Alice's balance on Chain 1 is validated in inflow-fulfill-hub-intent.sh (hub intent fulfillment)
BOB_CHAIN2_ADDRESS=$(get_profile_address "bob-chain2")
BOB_CHAIN2_BALANCE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' 2>/dev/null || echo "0")

# Remove commas
BOB_CHAIN2_BALANCE=$(echo "$BOB_CHAIN2_BALANCE" | tr -d ',')

# For inflow flow:
# - Bob on Chain 2 should have received ~1 APT from escrow release
# We check that balance increased by approximately the expected amount (at least 99% to account for gas)
# Note: Alice's balance on Chain 1 is validated in inflow-fulfill-hub-intent.sh (hub intent fulfillment)

EXPECTED_ESCROW_AMOUNT=100000000
MIN_EXPECTED_AMOUNT=99000000  # 99% to account for gas

# Calculate balance increase
BOB_CHAIN2_BALANCE_INCREASE=$((BOB_CHAIN2_BALANCE - BOB_CHAIN2_BALANCE_INIT))

# Check if escrow was released (Bob on Chain 2 should have received funds)
# Bob's balance on Chain 2 should have increased by at least MIN_EXPECTED_AMOUNT
if [ "$BOB_CHAIN2_BALANCE_INCREASE" -lt "$MIN_EXPECTED_AMOUNT" ]; then
    log_and_echo "❌ ERROR: Bob on Chain 2 balance did not increase by expected amount!"
    log_and_echo "   Initial balance: $BOB_CHAIN2_BALANCE_INIT Octas"
    log_and_echo "   Final balance: $BOB_CHAIN2_BALANCE Octas"
    log_and_echo "   Balance increase: $BOB_CHAIN2_BALANCE_INCREASE Octas"
    log_and_echo "   Expected increase: at least $MIN_EXPECTED_AMOUNT Octas (after escrow release)"
    log_and_echo "   This indicates the escrow was not released or funds were not received"
    log ""
    log "🔍 Diagnostic Information:"
    log "========================================"
    log ""
    log "   Verifier approvals:"
    curl -s "http://127.0.0.1:3333/approvals" | jq '.' 2>/dev/null || log "      (Unable to query approvals)"
    log ""
    log "   Verifier events:"
    curl -s "http://127.0.0.1:3333/events" | jq '.data | {escrow_events: (.escrow_events | length), fulfillment_events: (.fulfillment_events | length), intent_events: (.intent_events | length)}' 2>/dev/null || log "      (Unable to query events)"
    log ""
    log "   Verifier log:"
    log "   + + + + + + + + + + + + + + + + + + + +"
    cat "$VERIFIER_LOG" 2>/dev/null || log "      (Log file not found)"
    log "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
fi

log "   ✅ Final balances validated:"
log "      Bob Chain 2: $BOB_CHAIN2_BALANCE_INIT → $BOB_CHAIN2_BALANCE Octas (+$BOB_CHAIN2_BALANCE_INCREASE, escrow released)"
log "      Note: Alice's balance on Chain 1 is validated in inflow-fulfill-hub-intent.sh (hub intent fulfillment)"

# ============================================================================
# SECTION 7: FINAL SUMMARY
# ============================================================================
log ""
display_balances_hub
display_balances_connected_mvm
log_and_echo ""

log ""
log_and_echo "ℹ️  Verifier is running in the background"
# Get VERIFIER_PID from environment or find it
if [ -z "$VERIFIER_PID" ]; then
    # Try to find verifier PID from process list
    VERIFIER_PID=$(pgrep -f "cargo.*trusted-verifier" | head -1 || pgrep -f "target/debug/trusted-verifier" | head -1 || echo "")
    if [ -z "$VERIFIER_PID" ]; then
        # Try to read from pid file
        if [ -f "$LOG_DIR/verifier.pid" ]; then
            VERIFIER_PID=$(cat "$LOG_DIR/verifier.pid" 2>/dev/null || echo "")
        fi
    fi
fi
if [ -n "$VERIFIER_PID" ]; then
    log_and_echo "   Verifier PID: $VERIFIER_PID"
    # Store PID for cleanup
    echo $VERIFIER_PID > "$LOG_DIR/verifier.pid"
else
    log_and_echo "   Verifier PID: (not found)"
fi
log_and_echo ""
log_and_echo "✨ Script complete! Verifier is monitoring events in the background."

