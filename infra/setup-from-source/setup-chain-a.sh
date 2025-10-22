#!/bin/bash

# Chain A Setup Script
# Ports: REST API 8010, Faucet 8011
# 
# This script:
# 1. Cleans up existing processes and CLI profiles
# 2. Cleans up blockchain data (keeps config files)
# 3. Generates fresh config files
# 4. Modifies ports for Chain A (8010/8011)
# 5. Starts the validator node
# 6. Starts the faucet service
# 7. Tests both services
# 8. Creates and funds alice and bob test accounts
# 9. Ready for testing (run ./infra/test-chain-a.sh to test accounts and transfers)

set -e

CHAIN_DIR="./infra/.aptos/chain-a"
NODE_CONFIG="$CHAIN_DIR/0/node.yaml"

echo "🔧 Setting up Chain A..."

# Clean up any existing processes
echo "📋 Cleaning up existing processes..."
pkill -f "aptos-node" || true
pkill -f "aptos node" || true
pkill -f "aptos-faucet-service" || true

# Clean up CLI profiles for fresh start
echo "🧹 Cleaning up CLI profiles..."
aptos config delete-profile --profile alice || true
aptos config delete-profile --profile bob || true
aptos config delete-profile --profile chain-a || true

# Clean up existing data (keep config files)
echo "🧹 Cleaning up existing data..."
if [ -d "$CHAIN_DIR" ]; then
    # Remove only state directories, keep config files
    rm -rf "$CHAIN_DIR/0" "$CHAIN_DIR/api" "$CHAIN_DIR/index-db" "$CHAIN_DIR/indexer-grpc" "$CHAIN_DIR/main" "$CHAIN_DIR/table-info" "$CHAIN_DIR/tokio-runtime" || true
fi

# Generate fresh config files
echo "⚙️  Generating fresh config files..."
# Start the config generation in background and kill it after configs are created
aptos node run-localnet --with-faucet --force-restart --assume-yes --test-dir "$CHAIN_DIR" > "$CHAIN_DIR/config-gen.log" 2>&1 &
CONFIG_PID=$!

# Wait for config generation, then forcefully stop
sleep 35
pkill -f "aptos node run-localnet" || true
kill $CONFIG_PID 2>/dev/null || true
wait $CONFIG_PID 2>/dev/null || true

# Check if config files were generated
if [ ! -f "$NODE_CONFIG" ]; then
    echo "❌ Error: Failed to generate node.yaml config file"
    exit 1
fi

# Modify config for custom ports
echo "🔧 Modifying config for ports 8010/8011..."
if [ -f "$NODE_CONFIG" ]; then
    sed -i.bak 's/0.0.0.0:8080/0.0.0.0:8010/g' "$NODE_CONFIG"
    sed -i.bak 's/0.0.0.0:9101/0.0.0.0:9111/g' "$NODE_CONFIG"
    sed -i.bak 's/0.0.0.0:9102/0.0.0.0:9112/g' "$NODE_CONFIG"
    echo "✅ Config modified successfully"
else
    echo "❌ Error: node.yaml not found at $NODE_CONFIG"
    exit 1
fi

# Start Chain A manually
echo "🚀 Starting Chain A on port 8010..."
RUST_LOG=warn infra/external/aptos-core/target/release/aptos-node -f "$NODE_CONFIG" > "$CHAIN_DIR/node.log" 2>&1 &
NODE_PID=$!

# Wait for node to start
echo "⏳ Waiting for Chain A to start..."
sleep 10

# Start Faucet Service
echo "🚰 Starting Faucet Service on port 8011..."
infra/external/aptos-core/target/release/aptos-faucet-service run-simple \
    --node-url http://127.0.0.1:8010 \
    --listen-port 8011 \
    --key-file-path "$CHAIN_DIR/mint.key" \
    --chain-id 4 > "$CHAIN_DIR/faucet.log" 2>&1 &
FAUCET_PID=$!

# Wait for faucet to start
echo "⏳ Waiting for Faucet to start..."
sleep 5

# Test Chain A
echo "🧪 Testing Chain A..."
if curl -s http://127.0.0.1:8010/v1 > /dev/null; then
    echo "✅ Chain A is running successfully!"
    echo "📊 Chain A Status:"
    curl -s http://127.0.0.1:8010/v1 | jq '.chain_id, .block_height, .node_role'
    echo ""
    
    # Test Faucet
    echo "🧪 Testing Faucet..."
    if curl -s http://127.0.0.1:8011/ > /dev/null; then
        echo "✅ Faucet is running successfully!"
    else
        echo "❌ Faucet failed to start"
        kill $FAUCET_PID 2>/dev/null || true
    fi
    
    echo ""
    echo "🔗 Chain A Endpoints:"
    echo "   REST API: http://127.0.0.1:8010"
    echo "   Faucet:   http://127.0.0.1:8011"
    echo ""
    echo "📁 Chain A Directory: $CHAIN_DIR"
    echo "🆔 Node PID: $NODE_PID"
    echo "🆔 Faucet PID: $FAUCET_PID"
    
    # Verify no existing accounts before creating new ones
    echo ""
    echo "🔍 Verifying no existing accounts..."
    EXISTING_PROFILES=$(aptos config show-profiles | jq -r '.Result | keys[]' 2>/dev/null || echo "")
    if [ -n "$EXISTING_PROFILES" ]; then
        echo "❌ Error: Found existing profiles: $EXISTING_PROFILES"
        echo "   Expected: No profiles should exist on fresh Chain A"
        echo "   Please clean up profiles manually or fix the cleanup process"
        kill $NODE_PID 2>/dev/null || true
        kill $FAUCET_PID 2>/dev/null || true
        exit 1
    else
        echo "✅ No existing profiles found - proceeding with account creation"
    fi
    
    # Create and fund test accounts
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
    
    # Verify balances
    echo ""
    echo "💰 Account Balances:"
    echo "Alice balance:"
    aptos account balance --profile alice
    echo "Bob balance:"
    aptos account balance --profile bob
else
    echo "❌ Chain A failed to start"
    kill $NODE_PID 2>/dev/null || true
    kill $FAUCET_PID 2>/dev/null || true
    exit 1
fi

echo "🎉 Chain A setup complete!"
