#!/bin/bash

echo "🚀 APTOS INTENT FRAMEWORK - SETUP AND DEPLOY"
echo "============================================="

# Change to the project directory
cd /home/ap/code/movement/intent-framework

echo ""
echo "🔗 Step 1: Setting up dual Docker chains..."
echo " ============================================="
./infra/setup-docker/setup-dual-chains.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to setup Docker chains"
    exit 1
fi

echo ""
echo "⚙️  Step 2: Configuring Aptos CLI for both chains..."
echo " ============================================="
# Configure Chain 1 (port 8080)
echo "   - Configuring Chain 1 (port 8080)..."
aptos init --profile local --network local --assume-yes

# Configure Chain 2 (port 8082)
echo "   - Configuring Chain 2 (port 8082)..."
aptos init --profile local2 --network custom --rest-url http://127.0.0.1:8082 --assume-yes

echo ""
echo "📦 Step 3: Deploying contracts to Chain 1..."
echo "   - Getting account address for Chain 1..."
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r ".Result.local.account")

echo "   - Deploying to Chain 1 with address: $CHAIN1_ADDRESS"
cd move-intent-framework
aptos move publish --profile local --named-addresses aptos_intent=$CHAIN1_ADDRESS

if [ $? -eq 0 ]; then
    echo "   ✅ Chain 1 deployment successful!"
else
    echo "   ❌ Chain 1 deployment failed!"
    exit 1
fi

echo ""
echo "📦 Step 4: Deploying contracts to Chain 2..."
echo "   - Getting account address for Chain 2..."
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r ".Result.local2.account")

echo "   - Deploying to Chain 2 with address: $CHAIN2_ADDRESS"
aptos move publish --profile local2 --named-addresses aptos_intent=$CHAIN2_ADDRESS

if [ $? -eq 0 ]; then
    echo "   ✅ Chain 2 deployment successful!"
else
    echo "   ❌ Chain 2 deployment failed!"
    exit 1
fi

echo ""
echo "🧪 Step 5: Running tests to verify deployment..."
aptos move test --dev

if [ $? -eq 0 ]; then
    echo "   ✅ Tests passed!"
else
    echo "   ❌ Tests failed!"
    exit 1
fi

echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo "======================="
echo "Chain 1 (local):"
echo "   REST API: http://127.0.0.1:8080"
echo "   Faucet:   http://127.0.0.1:8081"
echo "   Address:  $CHAIN1_ADDRESS"
echo ""
echo "Chain 2 (local2):"
echo "   REST API: http://127.0.0.1:8082"
echo "   Faucet:   http://127.0.0.1:8083"
echo "   Address:  $CHAIN2_ADDRESS"
echo ""
echo "📋 Useful commands:"
echo "   Stop chains:     ./infra/setup-docker/stop-dual-chains.sh"
echo "   View Chain 1:    aptos config show-profiles --profile local"
echo "   View Chain 2:    aptos config show-profiles --profile local2"
echo "   Test Chain 1:    aptos move test --profile local"
echo "   Test Chain 2:    aptos move test --profile local2"

echo ""
echo "✨ Setup and deployment script completed!"
