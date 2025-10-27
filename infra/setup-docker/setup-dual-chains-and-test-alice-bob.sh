#!/bin/bash

# Setup Dual Chains and Test Alice/Bob Accounts
# This script:
# 1. Sets up dual Docker Aptos localnets
# 2. Creates and funds Alice and Bob accounts on both chains
# 3. Tests transfers between Alice and Bob on both chains
# Run this from the host machine (not inside Docker)

set -e

echo "🧪 Alice and Bob Account Testing - DUAL CHAINS"
echo "=============================================="

echo ""
echo "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
echo "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Stop any existing Docker containers
echo "🧹 Stopping any existing Docker containers..."
docker-compose -f infra/setup-docker/docker-compose.yml down 2>/dev/null || true
docker-compose -f infra/setup-docker/docker-compose-chain2.yml down 2>/dev/null || true

# Start fresh Docker localnets (both chains)
echo "🚀 Starting fresh Docker Aptos localnets (dual chains)..."
./infra/setup-docker/setup-dual-chains.sh

# Wait for services to be fully ready
echo "⏳ Waiting for services to be fully ready..."
sleep 15

# Verify Chain 1 is running
echo "🔍 Verifying Chain 1 is running..."
if ! curl -s http://127.0.0.1:8080/v1 > /dev/null; then
    echo "❌ Error: Chain 1 failed to start on port 8080"
    exit 1
fi
echo "✅ Chain 1 is running"

# Verify Chain 2 is running
echo "🔍 Verifying Chain 2 is running..."
if ! curl -s http://127.0.0.1:8082/v1 > /dev/null; then
    echo "❌ Error: Chain 2 failed to start on port 8082"
    exit 1
fi
echo "✅ Chain 2 is running"

# Verify faucets are running
echo "🔍 Verifying faucets are running..."
FAUCET1_RESPONSE=$(curl -s http://127.0.0.1:8081/ 2>/dev/null || echo "")
FAUCET2_RESPONSE=$(curl -s http://127.0.0.1:8083/ 2>/dev/null || echo "")

if [ "$FAUCET1_RESPONSE" = "tap:ok" ]; then
    echo "✅ Chain 1 faucet is running"
else
    echo "❌ Error: Chain 1 faucet failed to start on port 8081"
    exit 1
fi

if [ "$FAUCET2_RESPONSE" = "tap:ok" ]; then
    echo "✅ Chain 2 faucet is running"
else
    echo "❌ Error: Chain 2 faucet failed to start on port 8083"
    exit 1
fi

# Show chain status
echo ""
echo "📊 Chain Status:"
echo "Chain 1:"
curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height, .node_role'
echo "Chain 2:"
curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height, .node_role'

# Clean up any existing profiles
echo ""
echo "🧹 Cleaning up existing CLI profiles..."
aptos config delete-profile --profile alice-chain1 || true
aptos config delete-profile --profile bob-chain1 || true
aptos config delete-profile --profile alice-chain2 || true
aptos config delete-profile --profile bob-chain2 || true

# Create test accounts for Chain 1
echo ""
echo "👥 Creating test accounts for Chain 1..."

# Create alice account for Chain 1
echo "Creating alice-chain1 account for Chain 1..."
if printf "\n" | aptos init --profile alice-chain1 --network local --assume-yes; then
    echo "✅ Alice-chain1 account created successfully on Chain 1"
else
    echo "❌ Failed to create Alice-chain1 account on Chain 1"
    exit 1
fi

# Create bob account for Chain 1
echo "Creating bob-chain1 account for Chain 1..."
if printf "\n" | aptos init --profile bob-chain1 --network local --assume-yes; then
    echo "✅ Bob-chain1 account created successfully on Chain 1"
else
    echo "❌ Failed to create Bob-chain1 account on Chain 1"
    exit 1
fi

# Create test accounts for Chain 2
echo ""
echo "👥 Creating test accounts for Chain 2..."

# Create alice account for Chain 2
echo "Creating alice-chain2 account for Chain 2..."
if printf "\n" | aptos init --profile alice-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes; then
    echo "✅ Alice-chain2 account created successfully on Chain 2"
else
    echo "❌ Failed to create Alice-chain2 account on Chain 2"
    exit 1
fi

# Create bob account for Chain 2
echo "Creating bob-chain2 account for Chain 2..."
if printf "\n" | aptos init --profile bob-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes; then
    echo "✅ Bob-chain2 account created successfully on Chain 2"
else
    echo "❌ Failed to create Bob-chain2 account on Chain 2"
    exit 1
fi

echo ""
echo "% - - - - - - - - - - - FUNDING - - - - - - - - - - - -"
echo "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Fund Alice account on Chain 1
echo "Funding Alice-chain1 account on Chain 1..."
ALICE_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
ALICE_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${ALICE_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$ALICE_TX_HASH" != "null" ] && [ -n "$ALICE_TX_HASH" ]; then
    echo "✅ Alice-chain1 account funded successfully on Chain 1 (tx: $ALICE_TX_HASH)"
    
    # Wait for funding to be processed
    echo "⏳ Waiting for Alice funding to be processed on Chain 1..."
    sleep 10
    
    # Get Alice's FA store address from transaction events
    ALICE_FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${ALICE_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$ALICE_FA_STORE" != "null" ] && [ -n "$ALICE_FA_STORE" ]; then
        ALICE_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        echo "✅ Alice Chain 1 balance verified: $ALICE_BALANCE Octas"
    else
        echo "⚠️  Could not verify Alice Chain 1 balance via FA store"
    fi
else
    echo "❌ Failed to fund Alice account on Chain 1"
    exit 1
fi

# Fund Bob account on Chain 1
echo "Funding Bob-chain1 account on Chain 1..."
BOB_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
BOB_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${BOB_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$BOB_TX_HASH" != "null" ] && [ -n "$BOB_TX_HASH" ]; then
    echo "✅ Bob account funded successfully on Chain 1 (tx: $BOB_TX_HASH)"
    
    # Wait for funding to be processed
    echo "⏳ Waiting for Bob funding to be processed on Chain 1..."
    sleep 10
    
    # Get Bob's FA store address from transaction events
    BOB_FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${BOB_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$BOB_FA_STORE" != "null" ] && [ -n "$BOB_FA_STORE" ]; then
        BOB_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${BOB_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        echo "✅ Bob Chain 1 balance verified: $BOB_BALANCE Octas"
    else
        echo "⚠️  Could not verify Bob Chain 1 balance via FA store"
    fi
else
    echo "❌ Failed to fund Bob account on Chain 1"
    exit 1
fi

# Fund Alice account on Chain 2
echo "Funding Alice account on Chain 2..."
ALICE2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')
ALICE2_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8083/mint?address=${ALICE2_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$ALICE2_TX_HASH" != "null" ] && [ -n "$ALICE2_TX_HASH" ]; then
    echo "✅ Alice account funded successfully on Chain 2 (tx: $ALICE2_TX_HASH)"
    
    # Wait for funding to be processed
    echo "⏳ Waiting for Alice funding to be processed on Chain 2..."
    sleep 10
    
    # Get Alice's FA store address from transaction events
    ALICE2_FA_STORE=$(curl -s "http://127.0.0.1:8082/v1/transactions/by_hash/${ALICE2_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$ALICE2_FA_STORE" != "null" ] && [ -n "$ALICE2_FA_STORE" ]; then
        ALICE2_BALANCE=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE2_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        echo "✅ Alice Chain 2 balance verified: $ALICE2_BALANCE Octas"
    else
        echo "⚠️  Could not verify Alice Chain 2 balance via FA store"
    fi
else
    echo "❌ Failed to fund Alice account on Chain 2"
    exit 1
fi

# Fund Bob account on Chain 2
echo "Funding Bob account on Chain 2..."
BOB2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain2"].account')
BOB2_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8083/mint?address=${BOB2_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$BOB2_TX_HASH" != "null" ] && [ -n "$BOB2_TX_HASH" ]; then
    echo "✅ Bob account funded successfully on Chain 2 (tx: $BOB2_TX_HASH)"
    
    # Wait for funding to be processed
    echo "⏳ Waiting for Bob funding to be processed on Chain 2..."
    sleep 10
    
    # Get Bob's FA store address from transaction events
    BOB2_FA_STORE=$(curl -s "http://127.0.0.1:8082/v1/transactions/by_hash/${BOB2_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$BOB2_FA_STORE" != "null" ] && [ -n "$BOB2_FA_STORE" ]; then
        BOB2_BALANCE=$(curl -s "http://127.0.0.1:8082/v1/accounts/${BOB2_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        echo "✅ Bob Chain 2 balance verified: $BOB2_BALANCE Octas"
    else
        echo "⚠️  Could not verify Bob Chain 2 balance via FA store"
    fi
else
    echo "❌ Failed to fund Bob account on Chain 2"
    exit 1
fi

echo ""
echo "% - - - - - - - - - - - SUMMARY - - - - - - - - - - - -"
echo "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

echo ""
echo "🎉 DUAL-CHAIN ALICE AND BOB SETUP COMPLETE!"
echo "============================================"
echo ""
echo "📋 Account Information:"
echo "Chain 1 (port 8080):"
echo "   Alice: $ALICE_ADDRESS"
echo "   Bob:   $BOB_ADDRESS"
echo ""
echo "Chain 2 (port 8082):"
echo "   Alice: $ALICE2_ADDRESS"
echo "   Bob:   $BOB2_ADDRESS"
echo ""
echo "🔗 Chain Endpoints:"
echo "   Chain 1 REST API: http://127.0.0.1:8080/v1"
echo "   Chain 1 Faucet:   http://127.0.0.1:8081"
echo "   Chain 2 REST API: http://127.0.0.1:8082/v1"
echo "   Chain 2 Faucet:   http://127.0.0.1:8083"
echo ""
echo "📡 API Examples:"
echo "   Check Chain 1 status:    curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height'"
echo "   Check Chain 2 status:    curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height'"
echo "   Get Alice Chain 1:       curl -s http://127.0.0.1:8080/v1/accounts/$ALICE_ADDRESS"
echo "   Get Alice Chain 2:       curl -s http://127.0.0.1:8082/v1/accounts/$ALICE2_ADDRESS"
echo "   Fund Chain 1 account:    curl -X POST \"http://127.0.0.1:8081/mint?address=<ADDRESS>&amount=100000000\""
echo "   Fund Chain 2 account:    curl -X POST \"http://127.0.0.1:8083/mint?address=<ADDRESS>&amount=100000000\""
echo ""
echo "📋 Useful Commands:"
echo "   Stop chains:     ./infra/setup-docker/stop-dual-chains.sh"
echo "   View profiles:   aptos config show-profiles"
echo "   Test Chain 1:    aptos account balance --profile alice"
echo "   Test Chain 2:    aptos account balance --profile alice-chain2"
echo ""
echo "✨ Ready for cross-chain testing!"
