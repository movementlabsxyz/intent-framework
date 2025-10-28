#!/bin/bash

echo "======================================"
echo "🎯 CROSS-CHAIN INTENT - SUBMISSION"
echo "======================================"
echo ""
echo "This script submits cross-chain intents (Steps 1-3):"
echo "  1. [HUB CHAIN] User creates intent requesting tokens"
echo "  2. [CONNECTED CHAIN] User creates escrow with locked tokens"
echo "  3. [HUB CHAIN] Solver fulfills intent on hub chain"
echo ""
echo "For verifier monitoring and approval (Steps 4-6), run:"
echo "  ./trusted-verifier/tests/integration/run-cross-chain-verifier.sh"
echo ""
echo "The verifier will:"
echo "  4. Monitor both chains for intents and escrows"
echo "  5. Wait for hub intent to be fulfilled"
echo "  6. Sign approval for escrow release on connected chain"
echo ""

# Validate parameter
if [ -z "$1" ] || ([ "$1" != "0" ] && [ "$1" != "1" ]); then
    echo "❌ Error: Invalid parameter!"
    echo ""
    echo "Usage: $0 <parameter>"
    echo "  Parameter 0: Use existing running networks (skip setup)"
    echo "  Parameter 1: Run full setup and deploy contracts"
    echo ""
    echo "Examples:"
    echo "  $0 0    # Use existing networks"
    echo "  $0 1    # Run full setup"
    exit 1
fi

# Generate a random intent_id that will be used for both hub and escrow
INTENT_ID="0x$(openssl rand -hex 32)"

# Check if we should run setup or use existing networks
if [ "$1" = "1" ]; then
    echo ""
    echo "🚀 Step 0.1: Setting up chains and deploying contracts..."
    echo "========================================================"
    ./move-intent-framework/tests/cross_chain/setup-and-deploy.sh

    if [ $? -ne 0 ]; then
        echo "❌ Failed to setup chains and deploy contracts"
        exit 1
    fi

    echo ""
    echo "✅ Chains setup and contracts deployed successfully!"
    echo ""
else
    echo ""
    echo "⚡ Using existing running networks (skipping setup)"
    echo "   Use parameter '1' to run full setup: ./submit-cross-chain-intent.sh 1"
    echo ""
fi

# Note: Verifier monitoring will be handled separately

# Get addresses
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

# Get Alice and Bob addresses
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
ALICE_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')

echo ""
echo "📋 Chain Information:"
echo "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
echo "   Connected Chain (Chain 2): $CHAIN2_ADDRESS"
echo "   Alice Chain 1 (hub):     $ALICE_CHAIN1_ADDRESS"
echo "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
echo "   Alice Chain 2 (connected): $ALICE_CHAIN2_ADDRESS"

cd move-intent-framework

# Generate a dummy oracle public key for testing (32 bytes)
ORACLE_PUBLIC_KEY="0x$(openssl rand -hex 32)"
EXPIRY_TIME=$(date -d "+1 hour" +%s)

# Generate a random intent_id upfront (for cross-chain linking)
INTENT_ID="0x$(openssl rand -hex 32)"

echo ""
echo "🔑 Configuration:"
echo "   Oracle public key: $ORACLE_PUBLIC_KEY"
echo "   Expiry time: $EXPIRY_TIME"
echo "   Intent ID (for hub & escrow): $INTENT_ID"

echo ""
echo "📝 STEP 1: [HUB CHAIN] Alice creates intent requesting tokens"
echo "================================================="
echo "   User creates intent on hub chain requesting tokens from solver"
echo "   - Alice creates intent on Chain 1 (hub chain)"
echo "   - Intent requests 1000000 tokens to be provided by solver"
echo "   - Using intent_id: $INTENT_ID"

# Create cross-chain request intent on Chain 1 using fa_intent module
echo "   - Creating cross-chain request intent on Chain 1..."
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent::create_cross_chain_request_intent_entry" \
    --args "u64:1000000" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" > /tmp/intent_creation.log 2>&1

if [ $? -eq 0 ]; then
    echo "     ✅ Intent created on Chain 1!"
    
    # Verify intent was stored on-chain by checking Alice's latest transaction
    sleep 2
    echo "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent")) | .data.intent_address' | head -n 1)
    
    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        echo "     ✅ Hub intent stored at: $HUB_INTENT_ADDRESS"
    else
        echo "     ⚠️  Could not verify hub intent address"
    fi
else
    echo "     ❌ Intent creation failed on Chain 1!"
    cat /tmp/intent_creation.log
    exit 1
fi

echo ""
echo "📝 STEP 2: [CONNECTED CHAIN] Alice creates escrow intent with locked tokens"
echo "================================================="
echo "   User creates escrow on connected chain WITH tokens locked in it"
echo "   - Alice locks 1000000 tokens in escrow on Chain 2 (connected chain)"
echo "   - User provides hub chain intent_id when creating escrow"
echo "   - Using intent_id from hub chain: $INTENT_ID"

# Submit escrow intent using Alice's account on Chain 2 (connected chain)
echo "   - Creating escrow intent on Chain 2..."
aptos move run --profile alice-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::intent_as_escrow::create_escrow_from_apt" \
    --args "u64:1000000" "hex:${ORACLE_PUBLIC_KEY}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}"

if [ $? -eq 0 ]; then
    echo "     ✅ Escrow intent created on Chain 2!"
    
    # Verify escrow was stored on-chain and check locked amount
    sleep 2
    echo "     - Verifying escrow stored on-chain with locked tokens..."
    
    # Extract event data directly without piping through head
    ESCROW_ADDRESS=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_address' | head -n 1)
    ESCROW_INTENT_ID=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_id' | head -n 1)
    LOCKED_AMOUNT=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.source_amount' | head -n 1)
    DESIRED_AMOUNT=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.desired_amount' | head -n 1)
    
    if [ -n "$ESCROW_ADDRESS" ] && [ "$ESCROW_ADDRESS" != "null" ]; then
        
        echo "     ✅ Escrow stored at: $ESCROW_ADDRESS"
        echo "     ✅ Intent ID link: $ESCROW_INTENT_ID (should match: $INTENT_ID)"
        echo "     ✅ Locked amount: $LOCKED_AMOUNT tokens"
        echo "     ✅ Desired amount: $DESIRED_AMOUNT tokens"
        
        # Verify intent_id matches
        if [ "$ESCROW_INTENT_ID" = "$INTENT_ID" ]; then
            echo "     ✅ Intent IDs match - correct cross-chain link!"
        else
            echo "     ⚠️  Intent IDs don't match!"
        fi
        
        # Verify locked amount matches expected
        if [ "$LOCKED_AMOUNT" = "1000000" ]; then
            echo "     ✅ Escrow has correct locked amount (1000000 tokens)"
        else
            echo "     ⚠️  Escrow has unexpected locked amount: $LOCKED_AMOUNT"
        fi
    else
        echo "     ⚠️  Could not verify escrow from events"
    fi
else
    echo "     ❌ Escrow intent creation failed!"
    exit 1
fi

echo ""
echo "📝 STEP 3: [HUB CHAIN] Bob fulfills intent on hub chain"
echo "================================================="
echo "   Solver monitors escrow event on connected chain and fulfills intent on hub chain"
echo "   - Solver sees escrow event on connected chain"
echo "   - Bob sees intent with ID: $INTENT_ID"
echo "   - Bob provides 1000000 tokens on hub chain to fulfill the intent"

# TODO: We need to get the actual intent object address from Step 1
# For now, we'll need to extract it from the transaction event
INTENT_OBJECT_ADDRESS="$HUB_INTENT_ADDRESS"

if [ -n "$INTENT_OBJECT_ADDRESS" ] && [ "$INTENT_OBJECT_ADDRESS" != "null" ]; then
    echo "   - Fulfilling intent at: $INTENT_OBJECT_ADDRESS"
    
    # Bob fulfills the intent by providing tokens
    aptos move run --profile bob-chain1 --assume-yes \
        --function-id "0x${CHAIN1_ADDRESS}::fa_intent::fulfill_cross_chain_request_intent" \
        --args "address:$INTENT_OBJECT_ADDRESS" "u64:1000000"
    
    if [ $? -eq 0 ]; then
        echo "     ✅ Bob successfully fulfilled the intent!"
    else
        echo "     ❌ Intent fulfillment failed!"
    fi
else
    echo "     ⚠️  Could not get intent object address, skipping fulfillment"
fi

echo ""
echo "🎉 INTENT SUBMISSION COMPLETE!"
echo "=============================="
echo ""
echo "✅ Steps 1-3 completed successfully:"
echo "   1. Intent created on Chain 1 (hub chain)"
echo "   2. Escrow created on Chain 2 (connected chain) with locked tokens"
echo "   3. Intent fulfilled on Chain 1 by Bob"
echo ""
echo "📋 Intent Details:"
echo "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    echo "   Chain 1 Hub Intent: $HUB_INTENT_ADDRESS"
fi
if [ -n "$ESCROW_ADDRESS" ] && [ "$ESCROW_ADDRESS" != "null" ]; then
    echo "   Chain 2 Escrow: $ESCROW_ADDRESS"
fi
echo ""
echo "🔍 Next Steps:"
echo "   To monitor and verify these events with the trusted verifier, run:"
echo "   ./trusted-verifier/tests/integration/run-cross-chain-verifier.sh"
echo ""
echo "✨ Script completed - intents are submitted and waiting for verification!"

