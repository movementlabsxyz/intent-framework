#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "release-escrow-evm"
cd "$PROJECT_ROOT"

log "🔓 EVM ESCROW RELEASE"
log "====================="
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""

log "This script will:"
log "  1. Start the trusted verifier service"
log "  2. Monitor events on Chain 1 (hub) for intents and fulfillments"
log "  3. When fulfillment detected, create ECDSA signature"
log "  4. Release escrow on Chain 3 (EVM)"
log ""

# Start verifier (function handles stopping existing, starting, health checks, and initial polling wait)
start_verifier "$LOG_DIR/verifier-evm.log"

log ""

# Get EVM escrow contract address
cd evm-intent-framework
ESCROW_ADDRESS=$(grep -i "IntentEscrow deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-contract"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
cd ..

if [ -z "$ESCROW_ADDRESS" ]; then
    log_and_echo "❌ Could not find escrow contract address"
    exit 1
fi

log "   Escrow contract address: $ESCROW_ADDRESS"

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
        
        # Skip if already released
        if [[ "$RELEASED_ESCROWS" == *"$ESCROW_ID"* ]]; then
            continue
        fi
        
        log ""
        log "   📦 New approval found for escrow: $ESCROW_ID"
        log "   🔓 Releasing escrow on EVM chain..."
        
        # Convert intent_id to EVM format
        INTENT_ID_EVM=$(convert_intent_id_to_evm "$INTENT_ID")
        
        # Convert signature from base64 to hex for EVM
        # The verifier provides ECDSA signature as base64-encoded bytes (65 bytes: r || s || v)
        SIGNATURE_HEX=$(echo "$SIGNATURE_BASE64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')
        
        if [ -z "$SIGNATURE_HEX" ]; then
            log "   ❌ Failed to decode signature"
            continue
        fi
        
        # Signature should be 130 hex chars (65 bytes * 2)
        if [ ${#SIGNATURE_HEX} -ne 130 ]; then
            log "   ❌ Invalid signature length: expected 130 hex chars, got ${#SIGNATURE_HEX}"
            continue
        fi
        
        # Get Bob's balance before claiming (to verify funds were received)
        log "   - Getting Bob's balance before claim..."
        cd evm-intent-framework
        BOB_BALANCE_BEFORE_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
        BOB_BALANCE_BEFORE=$(echo "$BOB_BALANCE_BEFORE_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
        cd ..
        
        if [ -z "$BOB_BALANCE_BEFORE" ]; then
            log_and_echo "   ❌ ERROR: Failed to get Bob's balance before claim"
            log_and_echo "   Balance output: $BOB_BALANCE_BEFORE_OUTPUT"
            exit 1
        fi
        
        log "   - Bob's balance before claim: $BOB_BALANCE_BEFORE wei"
        
        # Submit escrow release transaction on EVM
        cd evm-intent-framework
        
        log "   - Calling IntentEscrow.claim() on EVM..."
        CLAIM_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ESCROW_ADDRESS='$ESCROW_ADDRESS' INTENT_ID_EVM='$INTENT_ID_EVM' SIGNATURE_HEX='$SIGNATURE_HEX' npx hardhat run scripts/claim-escrow.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
        
        TX_EXIT_CODE=$?
        cd ..
        
        if [ $TX_EXIT_CODE -ne 0 ]; then
            log_and_echo "   ❌ ERROR: Failed to release escrow on EVM chain"
            log_and_echo "   Claim output: $CLAIM_OUTPUT"
            log_and_echo "   Log file contents:"
            cat "$LOG_FILE"
            exit 1
        fi
        
        # Verify claim succeeded by checking for success message
        if ! echo "$CLAIM_OUTPUT" | grep -qi "Escrow released successfully"; then
            log_and_echo "   ❌ ERROR: Escrow claim did not complete successfully"
            log_and_echo "   Claim output: $CLAIM_OUTPUT"
            log_and_echo "   Expected to see 'Escrow released successfully' in output"
            exit 1
        fi
        
        # Wait a bit for transaction to be processed
        sleep 2
        
        # Get Bob's balance after claiming (to verify funds were received)
        log "   - Getting Bob's balance after claim..."
        cd evm-intent-framework
        BOB_BALANCE_AFTER_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1)
        BOB_BALANCE_AFTER=$(echo "$BOB_BALANCE_AFTER_OUTPUT" | grep -E '^[0-9]+$' | tail -1 | tr -d '\n')
        cd ..
        
        if [ -z "$BOB_BALANCE_AFTER" ]; then
            log_and_echo "   ❌ ERROR: Failed to get Bob's balance after claim"
            log_and_echo "   Balance output: $BOB_BALANCE_AFTER_OUTPUT"
            exit 1
        fi
        
        log "   - Bob's balance after claim: $BOB_BALANCE_AFTER wei"
        
        # Calculate balance increase
        # Expected: Bob should receive 1000 ETH = 1000000000000000000000 wei (minus gas fees)
        EXPECTED_AMOUNT_WEI="1000000000000000000000"  # 1000 ETH
        BALANCE_INCREASE=$(echo "$BOB_BALANCE_AFTER $BOB_BALANCE_BEFORE" | awk '{print $1 - $2}')
        
        log "   - Balance increase: $BALANCE_INCREASE wei"
        log "   - Expected: ~$EXPECTED_AMOUNT_WEI wei (1000 ETH minus gas)"
        
        # Check if balance increased by at least 99% of expected (allowing for gas fees)
        MIN_EXPECTED=$(echo "$EXPECTED_AMOUNT_WEI" | awk '{print int($1 * 0.99)}')
        
        # Use awk for numeric comparison
        SUFFICIENT_INCREASE=$(echo "$BALANCE_INCREASE $MIN_EXPECTED" | awk '{if ($1 >= $2) print "1"; else print "0"}')
        
        if [ "$SUFFICIENT_INCREASE" = "0" ] || [ -z "$BALANCE_INCREASE" ] || [ "$BALANCE_INCREASE" = "0" ]; then
            log_and_echo "   ❌ ERROR: Bob did not receive the escrow funds!"
            log_and_echo "   Bob's balance before: $BOB_BALANCE_BEFORE wei"
            log_and_echo "   Bob's balance after:  $BOB_BALANCE_AFTER wei"
            log_and_echo "   Balance increase:    $BALANCE_INCREASE wei"
            log_and_echo "   Expected increase:   ~$EXPECTED_AMOUNT_WEI wei (1000 ETH)"
            log_and_echo "   Minimum expected:     $MIN_EXPECTED wei (99% of 1000 ETH)"
            log_and_echo "   Escrow release FAILED - Bob did not receive funds!"
            exit 1
        fi
        
        log "   ✅ Escrow released successfully on EVM chain!"
        log "   ✅ Bob received $BALANCE_INCREASE wei (expected ~$EXPECTED_AMOUNT_WEI wei)"
        RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
    done
}

log ""
log "⏳ Polling verifier for approvals..."
log "   Verifier API: http://127.0.0.1:3333/approvals"
log ""

# Poll for approvals a few times before script exits
log "   - Checking for approvals (will check 10 times with 3 second intervals)..."
for i in {1..10}; do
    sleep 3
    check_and_release_escrows
done

log ""
# Check if any escrows were released
if [ -z "$RELEASED_ESCROWS" ]; then
    log_and_echo "❌ ERROR: No escrows were released!"
    log_and_echo "   The verifier may not have approved the escrow, or the claim failed"
    log_and_echo "   Verifier log:"
    cat "$VERIFIER_LOG"
    exit 1
fi

log "✅ Escrow release monitoring complete!"
log "   Released escrows: $RELEASED_ESCROWS"
log ""
log "📝 Useful commands:"
log "   View approvals:  curl -s http://127.0.0.1:3333/approvals | jq"
log "   View events:    curl -s http://127.0.0.1:3333/events | jq"
log "   Health check:   curl -s http://127.0.0.1:3333/health"

