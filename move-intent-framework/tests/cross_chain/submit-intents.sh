#!/bin/bash

echo "🎯 INTENT FRAMEWORK - SUBMIT ESCROW INTENT"
echo "==========================================="

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

# Check if we should run setup or use existing networks
if [ "$1" = "1" ]; then
    echo ""
    echo "🚀 Step 0: Setting up chains and deploying contracts..."
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
    echo "   Use parameter '1' to run full setup: ./submit-intents.sh 1"
    echo ""
fi

# Get addresses
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

echo ""
echo "📋 Chain Information:"
echo "   Chain 1 (intent-account-chain1):  $CHAIN1_ADDRESS"
echo "   Chain 2 (intent-account-chain2): $CHAIN2_ADDRESS"

echo ""
echo "💰 Step 1: Using existing Alice and Bob accounts..."

# Get Alice and Bob addresses (they're already set up from previous script)
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
ALICE_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')
BOB_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain2"].account')

echo "   - Alice Chain 1: $ALICE_CHAIN1_ADDRESS"
echo "   - Bob Chain 1:   $BOB_CHAIN1_ADDRESS"
echo "   - Alice Chain 2: $ALICE_CHAIN2_ADDRESS"
echo "   - Bob Chain 2:   $BOB_CHAIN2_ADDRESS"
echo "   ✅ Alice and Bob accounts already funded from previous setup!"

cd move-intent-framework

echo ""
echo "🎯 Step 2: Creating escrow intent on Chain 1..."

# Generate a dummy oracle public key for testing (32 bytes)
ORACLE_PUBLIC_KEY="0x$(openssl rand -hex 32)"
EXPIRY_TIME=$(date -d "+1 hour" +%s)

echo "   - Oracle public key: $ORACLE_PUBLIC_KEY"
echo "   - Expiry time: $EXPIRY_TIME"

# Submit escrow intent using Alice's account on Chain 1
echo "   - Creating escrow intent using Alice's account..."
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::intent_as_escrow::create_escrow_from_apt" \
    --args "u64:1000000" "hex:${ORACLE_PUBLIC_KEY}" "u64:${EXPIRY_TIME}"

if [ $? -eq 0 ]; then
    echo "     ✅ Alice-chain1 escrow intent created successfully!"
else
    echo "     ❌ Alice-chain1 escrow intent creation failed!"
fi

echo ""
echo "🎯 Step 3: Creating escrow intent using Bob's account on Chain 1..."

# Submit escrow intent using Bob's account on Chain 1
echo "   - Creating escrow intent using Bob's account..."
aptos move run --profile bob-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::intent_as_escrow::create_escrow_from_apt" \
    --args "u64:1000000" "hex:${ORACLE_PUBLIC_KEY}" "u64:${EXPIRY_TIME}"

if [ $? -eq 0 ]; then
    echo "     ✅ Bob-chain1 escrow intent created successfully!"
else
    echo "     ❌ Bob-chain1 escrow intent creation failed!"
fi

echo ""
echo "🎯 Step 4: Creating escrow intent using Alice's account on Chain 2..."

# Submit escrow intent using Alice's account on Chain 2
echo "   - Creating escrow intent using Alice's account..."
aptos move run --profile alice-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::intent_as_escrow::create_escrow_from_apt" \
    --args "u64:1000000" "hex:${ORACLE_PUBLIC_KEY}" "u64:${EXPIRY_TIME}"

if [ $? -eq 0 ]; then
    echo "     ✅ Alice-chain2 escrow intent created successfully!"
else
    echo "     ❌ Alice-chain2 escrow intent creation failed!"
fi

echo ""
echo "🎯 Step 5: Creating escrow intent using Bob's account on Chain 2..."

# Submit escrow intent using Bob's account on Chain 2
echo "   - Creating escrow intent using Bob's account..."
aptos move run --profile bob-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::intent_as_escrow::create_escrow_from_apt" \
    --args "u64:1000000" "hex:${ORACLE_PUBLIC_KEY}" "u64:${EXPIRY_TIME}"

if [ $? -eq 0 ]; then
    echo "     ✅ Bob-chain2 escrow intent created successfully!"
else
    echo "     ❌ Bob-chain2 escrow intent creation failed!"
fi

echo ""
echo "🎉 ESCROW INTENT SUBMISSION COMPLETE!"
echo "====================================="
echo ""
echo "Both chains now have escrow intents created!"
echo "   - Chain 1: http://127.0.0.1:8080"
echo "   - Chain 2: http://127.0.0.1:8082"
echo ""
echo "📋 What we accomplished:"
echo "   ✅ Used existing Alice and Bob accounts (already funded)"
echo "   ✅ Created escrow intents with APT tokens on both chains"
echo "   ✅ Used the deployed Intent Framework contracts"
echo "   ✅ Each escrow intent contains 1,000,000 octas (0.01 APT)"
echo ""
echo "🔑 Oracle Public Key used: $ORACLE_PUBLIC_KEY"
echo "⏰ Expiry Time: $EXPIRY_TIME ($(date -d "@$EXPIRY_TIME"))"
echo ""
echo "🔍 VERIFY ESCROW INTENTS WITH CURL COMMANDS:"
echo "============================================="
echo ""
echo "📜 Check Transaction History (shows intent creation):"
echo "   Alice Chain 1: curl -s \"http://127.0.0.1:8080/v1/accounts/$ALICE_CHAIN1_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"TradeIntent\"))'"
echo "   Bob Chain 1:   curl -s \"http://127.0.0.1:8080/v1/accounts/$BOB_CHAIN1_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"TradeIntent\"))'"
echo "   Alice Chain 2: curl -s \"http://127.0.0.1:8082/v1/accounts/$ALICE_CHAIN2_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"TradeIntent\"))'"
echo "   Bob Chain 2:   curl -s \"http://127.0.0.1:8082/v1/accounts/$BOB_CHAIN2_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"TradeIntent\"))'"
echo ""
echo "💰 Check APT Balance Changes (should be ~198M now, 1M withdrawn):"
echo "   Alice Chain 1: curl -s \"http://127.0.0.1:8080/v1/accounts/$ALICE_CHAIN1_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"FungibleStore\")) | .data.data.balance'"
echo "   Bob Chain 1:   curl -s \"http://127.0.0.1:8080/v1/accounts/$BOB_CHAIN1_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"FungibleStore\")) | .data.data.balance'"
echo "   Alice Chain 2: curl -s \"http://127.0.0.1:8082/v1/accounts/$ALICE_CHAIN2_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"FungibleStore\")) | .data.data.balance'"
echo "   Bob Chain 2:   curl -s \"http://127.0.0.1:8082/v1/accounts/$BOB_CHAIN2_ADDRESS/transactions\" | jq '.[0].changes[] | select(.data.type | contains(\"FungibleStore\")) | .data.data.balance'"
echo ""
echo "🎯 Check Intent Events (shows intent creation events):"
echo "   Alice Chain 1: curl -s \"http://127.0.0.1:8080/v1/accounts/$ALICE_CHAIN1_ADDRESS/transactions\" | jq '.[0].events[] | select(.type | contains(\"OracleLimitOrderEvent\"))'"
echo "   Bob Chain 1:   curl -s \"http://127.0.0.1:8080/v1/accounts/$BOB_CHAIN1_ADDRESS/transactions\" | jq '.[0].events[] | select(.type | contains(\"OracleLimitOrderEvent\"))'"
echo "   Alice Chain 2: curl -s \"http://127.0.0.1:8082/v1/accounts/$ALICE_CHAIN2_ADDRESS/transactions\" | jq '.[0].events[] | select(.type | contains(\"OracleLimitOrderEvent\"))'"
echo "   Bob Chain 2:   curl -s \"http://127.0.0.1:8082/v1/accounts/$BOB_CHAIN2_ADDRESS/transactions\" | jq '.[0].events[] | select(.type | contains(\"OracleLimitOrderEvent\"))'"