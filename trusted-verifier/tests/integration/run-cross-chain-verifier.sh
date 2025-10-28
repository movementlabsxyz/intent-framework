#!/bin/bash

echo "🔍 CROSS-CHAIN VERIFIER - STARTING MONITORING"
echo "=============================================="
echo ""
echo "This script will:"
echo "  1. Start the trusted verifier service"
echo "  2. Monitor events on Chain 1 (hub) and Chain 2 (connected)"
echo "  3. Validate cross-chain conditions match"
echo "  4. Wait for hub intent to be fulfilled by solver"
echo "  5. Provide approval signatures for escrow release after hub fulfillment"
echo ""

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"
cd "$PROJECT_ROOT"

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
CHAIN1_DEPLOY_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_DEPLOY_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

echo "   ✅ Alice Chain 1: $ALICE_CHAIN1_ADDRESS"
echo "   ✅ Alice Chain 2: $ALICE_CHAIN2_ADDRESS"
echo "   ✅ Chain 1 Deployer: $CHAIN1_DEPLOY_ADDRESS"
echo "   ✅ Chain 2 Deployer: $CHAIN2_DEPLOY_ADDRESS"
echo ""

# Verify that the verifier.toml addresses match the deployed addresses
echo "   - Verifying configuration matches deployed addresses..."
VERIFIER_CHAIN1_ADDR=$(grep -A 5 "^\[hub_chain\]" trusted-verifier/config/verifier.toml | grep "intent_module_address" | sed 's/intent_module_address = "\(.*\)"/\1/')
VERIFIER_CHAIN2_ADDR=$(grep -A 5 "^\[connected_chain\]" trusted-verifier/config/verifier.toml | grep "intent_module_address" | sed 's/intent_module_address = "\(.*\)"/\1/')

# Remove 0x prefix for comparison
VERIFIER_CHAIN1_ADDR=$(echo "$VERIFIER_CHAIN1_ADDR" | sed 's/^0x//')
VERIFIER_CHAIN2_ADDR=$(echo "$VERIFIER_CHAIN2_ADDR" | sed 's/^0x//')
CHAIN1_DEPLOY_ADDRESS=$(echo "$CHAIN1_DEPLOY_ADDRESS" | sed 's/^0x//')
CHAIN2_DEPLOY_ADDRESS=$(echo "$CHAIN2_DEPLOY_ADDRESS" | sed 's/^0x//')

if [ "$VERIFIER_CHAIN1_ADDR" != "$CHAIN1_DEPLOY_ADDRESS" ]; then
    echo "   ❌ ERROR: Chain 1 address mismatch!"
    echo "      Config: 0x$VERIFIER_CHAIN1_ADDR"
    echo "      Deployed: 0x$CHAIN1_DEPLOY_ADDRESS"
    echo ""
    echo "   Run setup-and-deploy.sh first, then update verifier.toml with:"
    echo "   intent_module_address = \"0x$CHAIN1_DEPLOY_ADDRESS\""
    exit 1
fi

if [ "$VERIFIER_CHAIN2_ADDR" != "$CHAIN2_DEPLOY_ADDRESS" ]; then
    echo "   ❌ ERROR: Chain 2 address mismatch!"
    echo "      Config: 0x$VERIFIER_CHAIN2_ADDR"
    echo "      Deployed: 0x$CHAIN2_DEPLOY_ADDRESS"
    echo ""
    echo "   Run setup-and-deploy.sh first, then update verifier.toml with:"
    echo "   intent_module_address = \"0x$CHAIN2_DEPLOY_ADDRESS\""
    exit 1
fi

echo "   ✅ Configuration addresses match deployed addresses"
echo ""

# Update verifier config with current account addresses
echo "   - Updating verifier configuration..."
# Update hub_chain known_accounts
sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\"]|" trusted-verifier/config/verifier.toml

# Update connected_chain known_accounts
sed -i "/\[connected_chain\]/,/\[verifier\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN2_ADDRESS\"]|" trusted-verifier/config/verifier.toml

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

if [ "$INTENT_COUNT" = "0" ] && [ "$ESCROW_COUNT" = "0" ]; then
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
fi

# Check for rejected intents in the logs
echo ""
echo "📋 Rejected Intents:"
echo "========================================"
REJECTED_COUNT=$(grep -c "SECURITY: Rejecting" /tmp/verifier.log 2>/dev/null || echo "0")

if [ "$REJECTED_COUNT" = "0" ]; then
    echo "   ✅ No intents rejected"
else
    echo "   ⚠️  Found $REJECTED_COUNT rejected intents (showing unique chain+intent combinations only):"
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
fi

echo ""
echo "🔍 Verifier is now monitoring:"
echo "   - Chain 1 (hub) at http://127.0.0.1:8080"
echo "   - Chain 2 (connected) at http://127.0.0.1:8082"
echo "   - API available at http://127.0.0.1:3000"
echo ""
echo "📝 Useful commands:"
echo "   View events:      curl -s http://127.0.0.1:3000/events | jq"
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

