#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_apt.sh"

# Setup project root and logging
setup_project_root
setup_logging "verifier_and_escrow_release"
cd "$PROJECT_ROOT"

echo "🔍 CROSS-CHAIN VERIFIER - STARTING MONITORING"
log "=============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

log "This script will:"
log "  1. Start the trusted verifier service"
log "  2. Monitor events on Chain 1 (hub) and Chain 2 (connected)"
log "  3. Validate cross-chain conditions match"
log "  4. Wait for hub intent to be fulfilled by solver"
log "  5. Provide approval signatures for escrow release after hub fulfillment"
log ""

# Get Alice and Bob addresses
log "   - Getting Alice and Bob account addresses..."
ALICE_CHAIN1_ADDRESS=$(get_profile_address "alice-chain1")
ALICE_CHAIN2_ADDRESS=$(get_profile_address "alice-chain2")
BOB_CHAIN1_ADDRESS=$(get_profile_address "bob-chain1")
BOB_CHAIN2_ADDRESS=$(get_profile_address "bob-chain2")
CHAIN1_DEPLOY_ADDRESS=$(get_profile_address "intent-account-chain1")
CHAIN2_DEPLOY_ADDRESS=$(get_profile_address "intent-account-chain2")

log "   ✅ Alice Chain 1: $ALICE_CHAIN1_ADDRESS"
log "   ✅ Alice Chain 2: $ALICE_CHAIN2_ADDRESS"
log "   ✅ Bob Chain 1: $BOB_CHAIN1_ADDRESS"
log "   ✅ Bob Chain 2: $BOB_CHAIN2_ADDRESS"
log "   ✅ Chain 1 Deployer: $CHAIN1_DEPLOY_ADDRESS"
log "   ✅ Chain 2 Deployer: $CHAIN2_DEPLOY_ADDRESS"
log ""

# Check and display initial balances using common function
log "   - Checking initial balances..."
display_balances

# Update verifier config with current deployed addresses and account addresses
log "   - Updating verifier configuration..."

# Setup verifier config
setup_verifier_config

# Update hub_chain intent_module_address
sed -i "/\[hub_chain\]/,/\[connected_chain_apt\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_DEPLOY_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Update connected_chain_apt intent_module_address
sed -i "/\[connected_chain_apt\]/,/\[verifier\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN2_DEPLOY_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Update connected_chain_apt escrow_module_address (same as intent_module_address)
sed -i "/\[connected_chain_apt\]/,/\[verifier\]/ s|escrow_module_address = .*|escrow_module_address = \"0x$CHAIN2_DEPLOY_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Update hub_chain known_accounts (include both Alice and Bob - Bob fulfills intents)
sed -i "/\[hub_chain\]/,/\[connected_chain_apt\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"

# Update connected_chain_apt known_accounts
sed -i "/\[connected_chain_apt\]/,/\[verifier\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN2_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"

log "   ✅ Updated verifier_testing.toml with:"
log "      Chain 1 intent_module_address: 0x$CHAIN1_DEPLOY_ADDRESS"
log "      Chain 2 intent_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
log "      Chain 2 escrow_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
log "      Chain 1 known_accounts: [$ALICE_CHAIN1_ADDRESS, $BOB_CHAIN1_ADDRESS]"
log "      Chain 2 known_accounts: $ALICE_CHAIN2_ADDRESS"
log ""

log ""
log "🚀 Starting Trusted Verifier Service..."
log "========================================"

# Start verifier (function handles stopping existing, starting, health checks, and initial polling wait)
start_verifier "$LOG_DIR/verifier.log" "info"


# Query verifier events
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
            "     source_metadata: \(.source_metadata)",
            "     source_amount: \(.source_amount)",
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
            "     source_metadata: \(.source_metadata)",
            "     source_amount: \(.source_amount)",
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

# Start automatic escrow release monitoring
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
            APPROVAL_VALUE=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].approval_value" 2>/dev/null | tr -d '\n\r\t ')
            SIGNATURE_BASE64=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].signature" 2>/dev/null | tr -d '\n\r\t ')
            
            if [ -z "$ESCROW_ID" ] || [ "$ESCROW_ID" = "null" ] || [ "$APPROVAL_VALUE" != "1" ]; then
                continue
            fi
            
            # Verify escrow_id is a valid object address format (66 chars: 0x + 64 hex)
            # Object addresses are 66 chars (0x + 64 hex), intent_ids are variable length
            if [ ${#ESCROW_ID} -lt 66 ] || ! echo "$ESCROW_ID" | grep -qE '^0x[0-9a-fA-F]{64}$'; then
                log_and_echo "   ❌ ERROR: escrow_id from approval is invalid: $ESCROW_ID"
                log_and_echo "   ❌ Expected format: 0x followed by 64 hex characters (66 chars total)"
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
                cat "$VERIFIER_LOG"
                exit 1
            fi
            
            # Skip if already released
            if [[ "$RELEASED_ESCROWS" == *"$ESCROW_ID"* ]]; then
                continue
            fi
            
            log ""
            log "   📦 New approval found for escrow: $ESCROW_ID"
            log "   🔓 Releasing escrow..."
            
            # Get Bob's balance before release (to verify funds were received)
            log "   - Getting Bob's balance before release..."
            BOB_BALANCE_BEFORE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' 2>/dev/null || echo "0")
            if [ -z "$BOB_BALANCE_BEFORE" ] || [ "$BOB_BALANCE_BEFORE" = "null" ]; then
                BOB_BALANCE_BEFORE="0"
            fi
            # Remove commas from balance if present
            BOB_BALANCE_BEFORE=$(echo "$BOB_BALANCE_BEFORE" | tr -d ',')
            log "   - Bob's balance before release: $BOB_BALANCE_BEFORE Octas"
            
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
            # Using bob-chain2 as solver (needs to have APT for payment)
            
            aptos move run --profile bob-chain2 --assume-yes \
                --function-id "0x${CHAIN2_DEPLOY_ADDRESS}::intent_as_escrow_entry::complete_escrow_from_fa" \
                --args "address:${ESCROW_ID}" "u64:${PAYMENT_AMOUNT}" "u64:${APPROVAL_VALUE}" "hex:${SIGNATURE_HEX}" >> "$LOG_FILE" 2>&1
            
            TX_EXIT_CODE=$?
            
            # Wait a bit for transaction to be processed
            sleep 2
            
            # Get Bob's balance after release
            log "   - Getting Bob's balance after release..."
            BOB_BALANCE_AFTER=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' 2>/dev/null || echo "0")
            if [ -z "$BOB_BALANCE_AFTER" ] || [ "$BOB_BALANCE_AFTER" = "null" ]; then
                BOB_BALANCE_AFTER="0"
            fi
            # Remove commas from balance if present
            BOB_BALANCE_AFTER=$(echo "$BOB_BALANCE_AFTER" | tr -d ',')
            log "   - Bob's balance after release: $BOB_BALANCE_AFTER Octas"
            
            # Calculate balance increase
            BALANCE_INCREASE=$((BOB_BALANCE_AFTER - BOB_BALANCE_BEFORE))
            
            # Expected amount: 100000000 tokens (locked in escrow) minus gas fees
            # We expect at least 99% of the locked amount to be received (allowing for gas)
            EXPECTED_MIN_AMOUNT=99000000
            
            if [ $TX_EXIT_CODE -eq 0 ]; then
                log "   ✅ Escrow release transaction succeeded!"
                
                # Verify Bob received the funds
                if [ "$BALANCE_INCREASE" -lt "$EXPECTED_MIN_AMOUNT" ]; then
                    log_and_echo "   ❌ ERROR: Bob did not receive escrow funds!"
                    log_and_echo "      Balance increase: $BALANCE_INCREASE Octas"
                    log_and_echo "      Expected minimum: $EXPECTED_MIN_AMOUNT Octas (100000000 minus gas)"
                    log_and_echo "      Bob balance before: $BOB_BALANCE_BEFORE Octas"
                    log_and_echo "      Bob balance after: $BOB_BALANCE_AFTER Octas"
                    log_and_echo "      Escrow ID: $ESCROW_ID"
                    exit 1
                fi
                
                log "   ✅ Bob received $BALANCE_INCREASE Octas (expected ~100000000 minus gas)"
                RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
            else
                # Check the log file for error messages
                ERROR_MSG=$(tail -100 "$LOG_FILE" | grep -oE "EOBJECT_DOES_NOT_EXIST|OBJECT_DOES_NOT_EXIST" || echo "")
                if [ -n "$ERROR_MSG" ]; then
                    # Escrow already released (object doesn't exist), verify Bob got the funds
                    log "   ℹ️  Escrow object no longer exists (may already be released)"
                    
                    # Verify Bob received the funds even though the object doesn't exist
                    if [ "$BALANCE_INCREASE" -lt "$EXPECTED_MIN_AMOUNT" ]; then
                        log_and_echo "   ❌ ERROR: Escrow object doesn't exist but Bob did NOT receive funds!"
                        log_and_echo "      Balance increase: $BALANCE_INCREASE Octas"
                        log_and_echo "      Expected minimum: $EXPECTED_MIN_AMOUNT Octas (100000000 minus gas)"
                        log_and_echo "      Bob balance before: $BOB_BALANCE_BEFORE Octas"
                        log_and_echo "      Bob balance after: $BOB_BALANCE_AFTER Octas"
                        log_and_echo "      Escrow ID: $ESCROW_ID"
                        log_and_echo "      This indicates the escrow was released but funds went to wrong address or were lost"
                        exit 1
                    fi
                    
                    log "   ✅ Verified: Bob received $BALANCE_INCREASE Octas (escrow was already released)"
                    RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
                else
                    log "   ❌ Failed to release escrow"
                    log_and_echo "   ❌ ERROR: Escrow release failed and Bob did not receive funds"
                    log_and_echo "   Log file contents:"
                    cat "$LOG_FILE"
                    log_and_echo "      Balance increase: $BALANCE_INCREASE Octas"
                    log_and_echo "      Expected minimum: $EXPECTED_MIN_AMOUNT Octas"
                    exit 1
                fi
            fi
        done
    }
    
    # Poll for approvals a few times before script exits
    log "   - Checking for approvals (will check 5 times with 3 second intervals)..."
    for i in {1..5}; do
        sleep 3
        check_and_release_escrows
    done
    
    log "   ✅ Initial approval check complete"
    log ""
    log "   ℹ️  The verifier will continue monitoring in the background"
    log "      To manually check and release escrows, use:"
    log "      curl -s http://127.0.0.1:3333/approvals | jq"
fi

# Check final balances using common function
display_balances

log_and_echo ""
log_and_echo "📝 Useful commands:"
log_and_echo "   View events:      curl -s http://127.0.0.1:3333/events | jq"
log_and_echo "   View approvals:  curl -s http://127.0.0.1:3333/approvals | jq"
log_and_echo "   Health check:     curl -s http://127.0.0.1:3333/health"
log_and_echo "   View logs:        tail -f $VERIFIER_LOG"
log_and_echo "   Stop verifier:    kill $VERIFIER_PID"
log_and_echo ""
log_and_echo "ℹ️  Verifier is running in the background"
log_and_echo "   Verifier PID: $VERIFIER_PID"
log_and_echo ""
log_and_echo "✨ Script complete! Verifier is monitoring events in the background."

# Store PID for cleanup
echo $VERIFIER_PID > "$LOG_DIR/verifier.pid"

