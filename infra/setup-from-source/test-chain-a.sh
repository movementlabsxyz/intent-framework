#!/bin/bash

# Test script for Chain A
# This script tests account creation, funding, and transfers on Chain A
# Run this after setup-chain-a.sh to verify everything works

set -e

echo "🧪 Chain A Test Script"
echo "======================"

# Check if Chain A is running
echo "🔍 Checking if Chain A is running..."
if ! curl -s http://127.0.0.1:8010/v1/ledger/info > /dev/null; then
    echo "❌ Error: Chain A is not running on port 8010"
    echo "Please run ./infra/setup-chain-a.sh first"
    exit 1
fi

echo "✅ Chain A is running"

# Check if faucet is running
echo "🔍 Checking if faucet is running..."
if ! curl -s http://127.0.0.1:8011/healthy > /dev/null; then
    echo "❌ Error: Faucet is not running on port 8011"
    echo "Please run ./infra/setup-chain-a.sh first"
    exit 1
fi

echo "✅ Faucet is running"

# Clean up any existing profiles
echo "🧹 Cleaning up existing CLI profiles..."
aptos config delete-profile --profile alice || true
aptos config delete-profile --profile bob || true
aptos config delete-profile --profile chain-a || true

# Create test accounts
echo ""
echo "👥 Creating test accounts..."

# Create alice account
echo "Creating alice account..."
echo "" | aptos init --profile alice --network custom --rest-url http://127.0.0.1:8010 --faucet-url http://127.0.0.1:8011 --assume-yes

# Create bob account  
echo "Creating bob account..."
echo "" | aptos init --profile bob --network custom --rest-url http://127.0.0.1:8010 --faucet-url http://127.0.0.1:8011 --assume-yes

# Fund both accounts
echo "Funding accounts..."
aptos account fund-with-faucet --profile alice --amount 100000000
aptos account fund-with-faucet --profile bob --amount 100000000

# Verify initial balances
echo ""
echo "💰 Initial Balances:"
echo "Alice balance:"
aptos account balance --profile alice
echo "Bob balance:"
aptos account balance --profile bob

# Test transfer between accounts
echo ""
echo "🔄 Testing transfer from Alice to Bob..."
BOB_ADDRESS=$(aptos config show-profiles | jq -r '.Result.bob.account')
TRANSFER_RESULT=$(printf "yes\n" | aptos account transfer --profile alice --account ${BOB_ADDRESS} --amount 5000000 --max-gas 10000)

# Check if transfer was successful
if echo "$TRANSFER_RESULT" | grep -q '"success": true'; then
    echo "✅ Transfer test successful!"
    
    # Wait for transaction to be processed
    echo "⏳ Waiting for transaction to be processed..."
    sleep 3
    
    # Verify final balances
    echo ""
    echo "💰 Final Balances After Transfer:"
    echo "Alice balance:"
    aptos account balance --profile alice
    echo "Bob balance:"
    aptos account balance --profile bob
    
    echo ""
    echo "🎉 All tests passed! Chain A is working correctly."
else
    echo "❌ Transfer test failed!"
    echo "Transfer result: $TRANSFER_RESULT"
    exit 1
fi
