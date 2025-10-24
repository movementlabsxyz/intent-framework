#!/bin/bash

echo "🚀 APTOS INTENT FRAMEWORK - SETUP AND DEPLOY"
echo "============================================="

# Change to the project directory
cd /home/ap/code/movement/intent-framework

echo ""
echo "🔗 Step 1: Setting up dual Docker chains with Alice and Bob accounts..."
echo " ============================================="
./infra/setup-docker/test-alice-bob-dual-chains.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to setup dual chains with Alice and Bob accounts"
    exit 1
fi

echo ""
echo "⚙️  Step 2: Configuring Aptos CLI for both chains..."
echo " ============================================="
# Configure Chain 1 (port 8080)
echo "   - Configuring Chain 1 (port 8080)..."
aptos init --profile intent-account-chain1 --network local --assume-yes

# Configure Chain 2 (port 8082)
echo "   - Configuring Chain 2 (port 8082)..."
aptos init --profile intent-account-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes

echo ""
echo "📦 Step 3: Deploying contracts to Chain 1..."
echo "   - Getting account address for Chain 1..."
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')

echo "   - Deploying to Chain 1 with address: $CHAIN1_ADDRESS"
cd move-intent-framework
aptos move publish --profile intent-account-chain1 --named-addresses aptos_intent=$CHAIN1_ADDRESS --assume-yes

if [ $? -eq 0 ]; then
    echo "   ✅ Chain 1 deployment successful!"
else
    echo "   ❌ Chain 1 deployment failed!"
    exit 1
fi

echo ""
echo "📦 Step 4: Deploying contracts to Chain 2..."
echo "   - Getting account address for Chain 2..."
cd ..
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

echo "   - Deploying to Chain 2 with address: $CHAIN2_ADDRESS"
cd move-intent-framework
aptos move publish --profile intent-account-chain2 --named-addresses aptos_intent=$CHAIN2_ADDRESS --assume-yes

if [ $? -eq 0 ]; then
    echo "   ✅ Chain 2 deployment successful!"
else
    echo "   ❌ Chain 2 deployment failed!"
    exit 1
fi

echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo "======================="
echo "Chain 1 (intent-account-chain1):"
echo "   REST API: http://127.0.0.1:8080/v1"
echo "   Faucet:   http://127.0.0.1:8081"
echo "   Account:  $CHAIN1_ADDRESS"
echo "   Contract: 0x${CHAIN1_ADDRESS}::aptos_intent"
echo ""
echo "Chain 2 (intent-account-chain2):"
echo "   REST API: http://127.0.0.1:8082/v1"
echo "   Faucet:   http://127.0.0.1:8083"
echo "   Account:  $CHAIN2_ADDRESS"
echo "   Contract: 0x${CHAIN2_ADDRESS}::aptos_intent"
echo ""
echo "📝 NOTE: The 'Account' is the deployer address, 'Contract' is the actual contract address"
echo "   Use the Contract address to call contract functions!"
echo ""
echo "📡 API Examples:"
echo "   Check Chain 1 status:    curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height'"
echo "   Check Chain 2 status:    curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height'"
echo "   Get Chain 1 account:     curl -s http://127.0.0.1:8080/v1/accounts/$CHAIN1_ADDRESS"
echo "   Get Chain 2 account:     curl -s http://127.0.0.1:8082/v1/accounts/$CHAIN2_ADDRESS"
echo "   Fund Chain 1 account:   curl -X POST \"http://127.0.0.1:8081/mint?address=<ADDRESS>&amount=100000000\""
echo "   Fund Chain 2 account:   curl -X POST \"http://127.0.0.1:8083/mint?address=<ADDRESS>&amount=100000000\""
echo ""
echo "📋 Useful commands:"
echo "   Stop chains:     ./infra/setup-docker/stop-dual-chains.sh"
echo "   View Chain 1:    aptos config show-profiles --profile intent-account-chain1"
echo "   View Chain 2:    aptos config show-profiles --profile intent-account-chain2"

echo ""
echo "✨ Setup and deployment script completed!"
