#!/bin/bash

# Alice and Bob Account Testing Script
# This script tests account creation, funding, and transfers on the Docker Aptos localnet
# Run this from the host machine (not inside Docker)

set -e

echo "🧪 Alice and Bob Account Testing"
echo "================================"

echo ""
echo "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
echo "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Stop any existing Docker containers
echo "🧹 Stopping any existing Docker containers..."
docker-compose -f testing-infra/single-chain/docker-compose.yml down 2>/dev/null || true

# Start fresh Docker localnet
echo "🚀 Starting fresh Docker Aptos localnet..."
./testing-infra/single-chain/setup-docker-chain.sh

# Wait for services to be fully ready
echo "⏳ Waiting for services to be fully ready..."
sleep 15

# Verify Docker localnet is running
echo "🔍 Verifying Docker localnet is running..."
if ! curl -s http://127.0.0.1:8080/v1 > /dev/null; then
    echo "❌ Error: Docker localnet failed to start on port 8080"
    exit 1
fi

echo "✅ Docker localnet is running"

# Verify faucet is running
echo "🔍 Verifying faucet is running..."
FAUCET_RESPONSE=$(curl -s http://127.0.0.1:8081/ 2>/dev/null || echo "")
if [ "$FAUCET_RESPONSE" = "tap:ok" ]; then
    echo "✅ Faucet is running"
else
    echo "❌ Error: Faucet failed to start on port 8081"
    echo "Faucet response: $FAUCET_RESPONSE"
    exit 1
fi

# Show chain status
echo ""
echo "📊 Chain Status:"
curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height, .node_role'

# Clean up any existing profiles
echo ""
echo "🧹 Cleaning up existing CLI profiles..."
aptos config delete-profile --profile alice || true
aptos config delete-profile --profile bob || true
aptos config delete-profile --profile local || true

# Create test accounts
echo ""
echo "👥 Creating test accounts..."

# Create alice account (non-interactive)
echo "Creating alice account..."
if printf "\n" | aptos init --profile alice --network local --assume-yes; then
    echo "✅ Alice account created successfully"
else
    echo "❌ Failed to create Alice account"
    exit 1
fi

# Create bob account (non-interactive)
echo "Creating bob account..."
if printf "\n" | aptos init --profile bob --network local --assume-yes; then
    echo "✅ Bob account created successfully"
else
    echo "❌ Failed to create Bob account"
    exit 1
fi

echo ""
echo "% - - - - - - - - - - - FUNDING - - - - - - - - - - - -"
echo "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

    # Fund Alice account using direct faucet API
    echo "Funding Alice account..."
    ALICE_ADDRESS=$(aptos config show-profiles | jq -r '.Result.alice.account')
    ALICE_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${ALICE_ADDRESS}&amount=100000000" | jq -r '.[0]')

    if [ "$ALICE_TX_HASH" != "null" ] && [ -n "$ALICE_TX_HASH" ]; then
        echo "✅ Alice account funded successfully (tx: $ALICE_TX_HASH)"

        # Wait for funding to be processed
        echo "⏳ Waiting for Alice funding to be processed..."
        sleep 10

        # Get Alice's FA store address from transaction events
        ALICE_FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${ALICE_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
        
        if [ -n "$ALICE_FA_STORE" ] && [ "$ALICE_FA_STORE" != "null" ]; then
            # Check Alice's balance in FA store
            ALICE_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
            
            if [ "$ALICE_BALANCE" != "null" ] && [ "$ALICE_BALANCE" != "" ]; then
                echo "✅ Alice on-chain funding verified - balance: $ALICE_BALANCE octas"
            else
                echo "❌ Alice on-chain funding verification failed - no balance found"
                exit 1
            fi
        else
            echo "❌ Alice on-chain funding verification failed - no FA store found"
            exit 1
        fi
    else
        echo "❌ Failed to fund Alice account"
        exit 1
    fi

# Fund Bob account using direct faucet API
echo "Funding Bob account..."
BOB_ADDRESS=$(aptos config show-profiles | jq -r '.Result.bob.account')
BOB_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${BOB_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$BOB_TX_HASH" != "null" ] && [ -n "$BOB_TX_HASH" ]; then
    echo "✅ Bob account funded successfully (tx: $BOB_TX_HASH)"

    # Wait for funding to be processed
    echo "⏳ Waiting for Bob funding to be processed..."
    sleep 10

    # Get Bob's FA store address from transaction events
    BOB_FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${BOB_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ -n "$BOB_FA_STORE" ] && [ "$BOB_FA_STORE" != "null" ]; then
        # Check Bob's balance in FA store
        BOB_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${BOB_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        
        if [ "$BOB_BALANCE" != "null" ] && [ "$BOB_BALANCE" != "" ]; then
            echo "✅ Bob on-chain funding verified - balance: $BOB_BALANCE octas"
        else
            echo "❌ Bob on-chain funding verification failed - no balance found"
            exit 1
        fi
    else
        echo "❌ Bob on-chain funding verification failed - no FA store found"
        exit 1
    fi
else
    echo "❌ Failed to fund Bob account"
    exit 1
fi

# Get account addresses
ALICE_ADDRESS=$(aptos config show-profiles | jq -r '.Result.alice.account')
BOB_ADDRESS=$(aptos config show-profiles | jq -r '.Result.bob.account')

echo ""
echo "💰 Initial On-Chain Balances Summary:"
echo "Alice FA Store: $ALICE_FA_STORE, Balance: $ALICE_BALANCE"
echo "Bob FA Store: $BOB_FA_STORE, Balance: $BOB_BALANCE"

echo ""
echo "% - - - - - - - - - - - TRANSFER - - - - - - - - - - - -"
echo "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Test transfer between accounts
echo "🔄 Testing transfer from Alice to Bob..."
echo "Bob's address: $BOB_ADDRESS"

# Send transaction from Alice to Bob (non-interactive)
TRANSFER_RESULT=$(printf "yes\n" | aptos account transfer --profile alice --account ${BOB_ADDRESS} --amount 2000000 --max-gas 10000)

# Extract transaction hash from the result
TX_HASH=$(echo "$TRANSFER_RESULT" | jq -r '.Result.hash' 2>/dev/null || echo "")

# Check if transfer was successful
if echo "$TRANSFER_RESULT" | grep -q '"success": true'; then
    echo "✅ Transfer test successful!"
    echo "Transaction hash: $TX_HASH"
    
    # Wait for transaction to be processed
    echo "⏳ Waiting for transaction to be processed..."
    sleep 3
    
    # Verify transfer on-chain by checking final balances
    echo ""
    echo "💰 Verifying Transfer On-Chain:"
    
    if [ -n "$ALICE_FA_STORE" ] && [ "$ALICE_FA_STORE" != "null" ]; then
        ALICE_FINAL_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance' 2>/dev/null)
        if [ -n "$ALICE_FINAL_BALANCE" ] && [ "$ALICE_FINAL_BALANCE" != "null" ]; then
            echo "✅ Alice final balance verified: $ALICE_FINAL_BALANCE"
        else
            echo "❌ Alice final balance verification failed"
            exit 1
        fi
    else
        echo "❌ Could not verify Alice final balance - FA store not found"
        exit 1
    fi
    
    if [ -n "$BOB_FA_STORE" ] && [ "$BOB_FA_STORE" != "null" ]; then
        BOB_FINAL_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${BOB_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance' 2>/dev/null)
        if [ -n "$BOB_FINAL_BALANCE" ] && [ "$BOB_FINAL_BALANCE" != "null" ]; then
            echo "✅ Bob final balance verified: $BOB_FINAL_BALANCE"
        else
            echo "❌ Bob final balance verification failed"
            exit 1
        fi
    else
        echo "❌ Could not verify Bob final balance - FA store not found"
        exit 1
    fi
    
    echo ""
    echo "🎉 All tests passed! Alice and Bob accounts are working correctly."
    
else
    echo "❌ Transfer test failed!"
    echo "Transfer result: $TRANSFER_RESULT"
    exit 1
fi

#echo ""
#echo "🧹 Cleaning up Docker containers..."
# docker-compose -f testing-infra/single-chain/docker-compose.yml down

echo ""
echo "🎯 Alice and Bob testing ended!"
