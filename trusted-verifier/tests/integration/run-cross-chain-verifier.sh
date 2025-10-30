#!/bin/bash

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"
cd "$PROJECT_ROOT"

# Validate parameter
if [ -z "$1" ] || ([ "$1" != "0" ] && [ "$1" != "1" ]); then
    echo "🔍 CROSS-CHAIN VERIFIER - USAGE"
    echo "=============================================="
    echo ""
    echo "Usage: $0 <parameter>"
    echo ""
    echo "Options:"
    echo "  0: Run verifier only (use existing running networks)"
    echo "  1: Run full setup + submit intents + verifier"
    echo ""
    echo "Examples:"
    echo "  $0 0    # Run verifier on existing networks"
    echo "  $0 1    # Setup, deploy, submit intents, then run verifier"
    echo ""
    exit 1
fi

echo "🔍 CROSS-CHAIN VERIFIER - STARTING MONITORING"
echo "=============================================="
echo ""

# If option 1, run submit script first (which does setup + submit)
if [ "$1" = "1" ]; then
    echo "🚀 Step 0: Running setup and submitting intents..."
    echo "================================================="
    ./move-intent-framework/tests/cross_chain/submit-cross-chain-intent.sh 1
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to setup and submit intents"
        exit 1
    fi
    
    echo ""
    echo "✅ Setup and intent submission complete!"
    echo ""
fi

echo "This script will:"
echo "  1. Start the trusted verifier service"
echo "  2. Monitor events on Chain 1 (hub) and Chain 2 (connected)"
echo "  3. Validate cross-chain conditions match"
echo "  4. Wait for hub intent to be fulfilled by solver"
echo "  5. Provide approval signatures for escrow release after hub fulfillment"
echo ""

# Check if verifier is already running and stop it
echo "   Checking for existing verifiers..."
# Look for the actual cargo/rust processes, not the script
if pgrep -f "cargo.*trusted-verifier" > /dev/null || pgrep -f "target/debug/trusted-verifier" > /dev/null; then
    echo "   ⚠️  Found existing verifier processes, stopping them..."
    pkill -f "cargo.*trusted-verifier"
    pkill -f "target/debug/trusted-verifier"
    sleep 2
else
    echo "   ✅ No existing verifier processes"
fi

# Get Alice and Bob addresses
echo "   - Getting Alice and Bob account addresses..."
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
ALICE_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
BOB_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain2"].account')
CHAIN1_DEPLOY_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_DEPLOY_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

echo "   ✅ Alice Chain 1: $ALICE_CHAIN1_ADDRESS"
echo "   ✅ Alice Chain 2: $ALICE_CHAIN2_ADDRESS"
echo "   ✅ Bob Chain 1: $BOB_CHAIN1_ADDRESS"
echo "   ✅ Bob Chain 2: $BOB_CHAIN2_ADDRESS"
echo "   ✅ Chain 1 Deployer: $CHAIN1_DEPLOY_ADDRESS"
echo "   ✅ Chain 2 Deployer: $CHAIN2_DEPLOY_ADDRESS"
echo ""

# Check initial balances
echo "   - Checking initial balances..."
echo ""
echo "   💰 Initial Balances:"
echo "   ====================="

ALICE_CHAIN1_BALANCE=$(aptos account balance --profile alice-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
ALICE_CHAIN2_BALANCE=$(aptos account balance --profile alice-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
BOB_CHAIN1_BALANCE=$(aptos account balance --profile bob-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
BOB_CHAIN2_BALANCE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")

echo "   Chain 1 (Hub):"
echo "      Alice: $ALICE_CHAIN1_BALANCE Octas"
echo "      Bob:   $BOB_CHAIN1_BALANCE Octas"
echo "   Chain 2 (Connected):"
echo "      Alice: $ALICE_CHAIN2_BALANCE Octas"
echo "      Bob:   $BOB_CHAIN2_BALANCE Octas"
echo ""

# Update verifier config with current deployed addresses and account addresses
echo "   - Updating verifier configuration..."

# Update hub_chain intent_module_address
sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_DEPLOY_ADDRESS\"|" trusted-verifier/config/verifier.toml

# Update connected_chain intent_module_address
sed -i "/\[connected_chain\]/,/\[verifier\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN2_DEPLOY_ADDRESS\"|" trusted-verifier/config/verifier.toml

# Update connected_chain escrow_module_address (same as intent_module_address)
sed -i "/\[connected_chain\]/,/\[verifier\]/ s|escrow_module_address = .*|escrow_module_address = \"0x$CHAIN2_DEPLOY_ADDRESS\"|" trusted-verifier/config/verifier.toml

# Update hub_chain known_accounts (include both Alice and Bob - Bob fulfills intents)
sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" trusted-verifier/config/verifier.toml

# Update connected_chain known_accounts
sed -i "/\[connected_chain\]/,/\[verifier\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN2_ADDRESS\"]|" trusted-verifier/config/verifier.toml

echo "   ✅ Updated verifier.toml with:"
echo "      Chain 1 intent_module_address: 0x$CHAIN1_DEPLOY_ADDRESS"
echo "      Chain 2 intent_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
echo "      Chain 2 escrow_module_address: 0x$CHAIN2_DEPLOY_ADDRESS"
echo "      Chain 1 known_accounts: [$ALICE_CHAIN1_ADDRESS, $BOB_CHAIN1_ADDRESS]"
echo "      Chain 2 known_accounts: $ALICE_CHAIN2_ADDRESS"
echo ""

echo ""
echo "🚀 Starting Trusted Verifier Service..."
echo "========================================"

# Change to trusted-verifier directory and start the verifier
pushd trusted-verifier > /dev/null
RUST_LOG=info cargo run --bin trusted-verifier > /tmp/verifier.log 2>&1 &
VERIFIER_PID=$!
popd > /dev/null

echo "   ✅ Verifier started with PID: $VERIFIER_PID"

# Wait for verifier to be ready
echo "   - Waiting for verifier to initialize..."
RETRY_COUNT=0
MAX_RETRIES=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -f "http://127.0.0.1:3000/health" > /dev/null 2>&1; then
        echo "   ✅ Verifier is ready!"
        break
    fi
    
    sleep 1
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "   ❌ Verifier failed to start after $MAX_RETRIES seconds"
        echo "   Check logs: tail -f /tmp/verifier.log"
        exit 1
    fi
done

echo ""
echo "📊 Monitoring verifier events..."
echo "   Waiting 5 seconds for verifier to poll and collect events..."

sleep 5

# Query verifier events
echo ""
echo "📋 Verifier Status:"
echo "========================================"

VERIFIER_EVENTS=$(curl -s "http://127.0.0.1:3000/events")

# Check if verifier has intent events
INTENT_COUNT=$(echo "$VERIFIER_EVENTS" | jq -r '.data.intent_events | length' 2>/dev/null || echo "0")
ESCROW_COUNT=$(echo "$VERIFIER_EVENTS" | jq -r '.data.escrow_events | length' 2>/dev/null || echo "0")
FULFILLMENT_COUNT=$(echo "$VERIFIER_EVENTS" | jq -r '.data.fulfillment_events | length' 2>/dev/null || echo "0")

if [ "$INTENT_COUNT" = "0" ] && [ "$ESCROW_COUNT" = "0" ] && [ "$FULFILLMENT_COUNT" = "0" ]; then
    echo "   ⚠️  No events monitored yet"
    echo "   Verifier is running and waiting for events"
else
    if [ "$INTENT_COUNT" != "0" ]; then
        echo "   ✅ Verifier has monitored $INTENT_COUNT intent events:"
        echo "$VERIFIER_EVENTS" | jq -r '.data.intent_events[] | 
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
            ""' 2>/dev/null || echo "     (Unable to parse events)"
    fi
    
    if [ "$ESCROW_COUNT" != "0" ]; then
        echo "   ✅ Verifier has monitored $ESCROW_COUNT escrow events:"
        echo "$VERIFIER_EVENTS" | jq -r '.data.escrow_events[] | 
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
            ""' 2>/dev/null || echo "     (Unable to parse events)"
    fi
    
    if [ "$FULFILLMENT_COUNT" != "0" ]; then
        echo "   ✅ Verifier has monitored $FULFILLMENT_COUNT fulfillment events:"
        echo "$VERIFIER_EVENTS" | jq -r '.data.fulfillment_events[] | 
            "     chain: \(.chain)",
            "     intent_id: \(.intent_id)",
            "     intent_address: \(.intent_address)",
            "     solver: \(.solver)",
            "     provided_metadata: \(.provided_metadata)",
            "     provided_amount: \(.provided_amount)",
            "     timestamp: \(.timestamp)",
            ""' 2>/dev/null || echo "     (Unable to parse events)"
    fi
fi

# Check for rejected intents in the logs
echo ""
echo "📋 Rejected Intents:"
echo "========================================"
REJECTED_COUNT=$(grep -c "SECURITY: Rejecting" /tmp/verifier.log 2>/dev/null || echo "0")
# Trim any whitespace and ensure it's a number
REJECTED_COUNT=$(echo "$REJECTED_COUNT" | tr -d ' \n\t' | head -1)
REJECTED_COUNT=${REJECTED_COUNT:-0}

# Use numeric comparison: only exit if count > 0
if [ "$REJECTED_COUNT" -eq 0 ] 2>/dev/null; then
    echo "   ✅ No intents rejected"
else
    echo "   ❌ ERROR: Found $REJECTED_COUNT rejected intents (showing unique chain+intent combinations only):"
    # Use associative array to track unique chain+intent combinations
    declare -A seen_keys
    
    grep -n "SECURITY: Rejecting" /tmp/verifier.log 2>/dev/null | while IFS= read -r line_with_num; do
        LINE_NUM=$(echo "$line_with_num" | cut -d: -f1)
        REJECTION_LINE=$(echo "$line_with_num" | cut -d: -f2-)
        
        # Extract details from log line
        INTENT_INFO=$(echo "$REJECTION_LINE" | grep -oE "intent [0-9a-fx]+" | sed 's/intent //')
        CREATOR_INFO=$(echo "$REJECTION_LINE" | grep -oE "from [0-9a-fx]+" | sed 's/from //')
        REASON=$(echo "$REJECTION_LINE" | sed 's/.*SECURITY: //' | sed 's/ - NOT safe for escrow.*/ - NOT safe for escrow/' || echo "Revocable intent")
        
        # Determine which chain by checking the line before the rejection
        PREV_LINE=$(sed -n "$((LINE_NUM-1))p" /tmp/verifier.log)
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
                echo "     ❌ Chain: $CHAIN"
                echo "        Intent: $INTENT_INFO"
                [ -n "$CREATOR_INFO" ] && echo "        Creator: $CREATOR_INFO"
                [ -n "$REASON" ] && echo "        Reason: $REASON"
                echo ""
            fi
        fi
    done
    
    # Panic if there are rejected intents
    echo ""
    echo "   ❌ FATAL: Rejected intents detected. Exiting..."
    exit 1
fi

echo ""
echo "🔍 Verifier is now monitoring:"
echo "   - Chain 1 (hub) at http://127.0.0.1:8080"
echo "   - Chain 2 (connected) at http://127.0.0.1:8082"
echo "   - API available at http://127.0.0.1:3000"
echo ""

# Start automatic escrow release monitoring
echo "🔓 Starting automatic escrow release monitoring..."
echo "=================================================="

# Get Chain 2 deployer address for function calls
CHAIN2_DEPLOY_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')
if [ -z "$CHAIN2_DEPLOY_ADDRESS" ] || [ "$CHAIN2_DEPLOY_ADDRESS" = "null" ]; then
    echo "   ⚠️  Warning: Could not find Chain 2 deployer address"
    echo "      Automatic escrow release will be disabled"
else
    echo "   ✅ Automatic escrow release enabled"
    echo "      Chain 2 deployer: 0x$CHAIN2_DEPLOY_ADDRESS"
    
    # Track released escrows to avoid duplicate attempts
    RELEASED_ESCROWS=""
    
    # Function to check for new approvals and release escrows
    check_and_release_escrows() {
        APPROVALS_RESPONSE=$(curl -s "http://127.0.0.1:3000/approvals")
        
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
            ESCROW_ID=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].escrow_id" 2>/dev/null)
            APPROVAL_VALUE=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].approval_value" 2>/dev/null)
            SIGNATURE_BASE64=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].signature" 2>/dev/null)
            
            if [ -z "$ESCROW_ID" ] || [ "$ESCROW_ID" = "null" ] || [ "$APPROVAL_VALUE" != "1" ]; then
                continue
            fi
            
            # Skip if already released
            if [[ "$RELEASED_ESCROWS" == *"$ESCROW_ID"* ]]; then
                continue
            fi
            
            echo ""
            echo "   📦 New approval found for escrow: $ESCROW_ID"
            echo "   🔓 Releasing escrow..."
            
            # Decode base64 signature to hex
            SIGNATURE_HEX=$(echo "$SIGNATURE_BASE64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')
            
            if [ -z "$SIGNATURE_HEX" ]; then
                echo "   ❌ Failed to decode signature"
                continue
            fi
            
            # Submit escrow release transaction
            # Using bob-chain2 as solver (needs to have APT for payment)
            PAYMENT_AMOUNT=1  # Placeholder amount
            
            aptos move run --profile bob-chain2 --assume-yes \
                --function-id "0x${CHAIN2_DEPLOY_ADDRESS}::intent_as_escrow_apt::complete_escrow_from_apt" \
                --args "address:${ESCROW_ID}" "u64:${PAYMENT_AMOUNT}" "u64:${APPROVAL_VALUE}" "hex:${SIGNATURE_HEX}" > /tmp/escrow_release_${ESCROW_ID}.log 2>&1
            
            TX_EXIT_CODE=$?
            
            if [ $TX_EXIT_CODE -eq 0 ]; then
                echo "   ✅ Escrow released successfully!"
                RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
            else
                ERROR_MSG=$(cat /tmp/escrow_release_${ESCROW_ID}.log | grep -oE "EOBJECT_DOES_NOT_EXIST|OBJECT_DOES_NOT_EXIST" || echo "")
                if [ -n "$ERROR_MSG" ]; then
                    # Escrow already released (object doesn't exist), mark as processed
                    echo "   ℹ️  Escrow already released (object no longer exists)"
                    RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
                else
                    echo "   ❌ Failed to release escrow"
                    echo "      Error: $(cat /tmp/escrow_release_${ESCROW_ID}.log | tail -5)"
                fi
            fi
        done
    }
    
    # Poll for approvals a few times before script exits
    echo "   - Checking for approvals (will check 5 times with 3 second intervals)..."
    for i in {1..5}; do
        sleep 3
        check_and_release_escrows
    done
    
    echo "   ✅ Initial approval check complete"
    echo ""
    echo "   ℹ️  The verifier will continue monitoring in the background"
    echo "      To manually check and release escrows, use:"
    echo "      curl -s http://127.0.0.1:3000/approvals | jq"
fi

# Check final balances
echo ""
echo "   💰 Final Balances:"
echo "   ==================="

FINAL_ALICE_CHAIN1_BALANCE=$(aptos account balance --profile alice-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
FINAL_ALICE_CHAIN2_BALANCE=$(aptos account balance --profile alice-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
FINAL_BOB_CHAIN1_BALANCE=$(aptos account balance --profile bob-chain1 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")
FINAL_BOB_CHAIN2_BALANCE=$(aptos account balance --profile bob-chain2 2>/dev/null | jq -r '.Result[0].balance // 0' || echo "0")

ALICE_CHAIN1_DIFF=$(($FINAL_ALICE_CHAIN1_BALANCE - $ALICE_CHAIN1_BALANCE))
BOB_CHAIN1_DIFF=$(($FINAL_BOB_CHAIN1_BALANCE - $BOB_CHAIN1_BALANCE))
ALICE_CHAIN2_DIFF=$(($FINAL_ALICE_CHAIN2_BALANCE - $ALICE_CHAIN2_BALANCE))
BOB_CHAIN2_DIFF=$(($FINAL_BOB_CHAIN2_BALANCE - $BOB_CHAIN2_BALANCE))

echo "   Chain 1 (Hub):"
if [ $ALICE_CHAIN1_DIFF -ge 0 ]; then
    echo "      Alice: $FINAL_ALICE_CHAIN1_BALANCE Octas (+$ALICE_CHAIN1_DIFF)"
else
    echo "      Alice: $FINAL_ALICE_CHAIN1_BALANCE Octas ($ALICE_CHAIN1_DIFF)"
fi
if [ $BOB_CHAIN1_DIFF -ge 0 ]; then
    echo "      Bob:   $FINAL_BOB_CHAIN1_BALANCE Octas (+$BOB_CHAIN1_DIFF)"
else
    echo "      Bob:   $FINAL_BOB_CHAIN1_BALANCE Octas ($BOB_CHAIN1_DIFF)"
fi
echo "   Chain 2 (Connected):"
if [ $ALICE_CHAIN2_DIFF -ge 0 ]; then
    echo "      Alice: $FINAL_ALICE_CHAIN2_BALANCE Octas (+$ALICE_CHAIN2_DIFF)"
else
    echo "      Alice: $FINAL_ALICE_CHAIN2_BALANCE Octas ($ALICE_CHAIN2_DIFF)"
fi
if [ $BOB_CHAIN2_DIFF -ge 0 ]; then
    echo "      Bob:   $FINAL_BOB_CHAIN2_BALANCE Octas (+$BOB_CHAIN2_DIFF)"
else
    echo "      Bob:   $FINAL_BOB_CHAIN2_BALANCE Octas ($BOB_CHAIN2_DIFF)"
fi
echo ""

echo ""
echo "📝 Useful commands:"
echo "   View events:      curl -s http://127.0.0.1:3000/events | jq"
echo "   View approvals:  curl -s http://127.0.0.1:3000/approvals | jq"
echo "   Health check:     curl -s http://127.0.0.1:3000/health"
echo "   View logs:        tail -f /tmp/verifier.log"
echo "   Stop verifier:    kill $VERIFIER_PID"
echo ""
echo "ℹ️  Verifier is running in the background"
echo "   Verifier PID: $VERIFIER_PID"
echo ""
echo "✨ Script complete! Verifier is monitoring events in the background."

# Store PID for cleanup
echo $VERIFIER_PID > /tmp/verifier.pid

