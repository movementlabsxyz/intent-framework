#!/bin/bash

# Chain B Setup Script
# Ports: REST API 8020, Faucet 8021
# 
# This script:
# 1. Cleans up existing processes and CLI profiles
# 2. Cleans up blockchain data (keeps config files)
# 3. Generates fresh config files
# 4. Modifies ports for Chain B (8020/8021)
# 5. Starts the validator node
# 6. Starts the faucet service
# 7. Tests both services
# 8. Creates and funds alice-chain-b and bob-chain-b test accounts
# 9. Ready for testing (run ./testing-infra/test-chain-b.sh to test accounts and transfers)

set -e

CHAIN_DIR="./testing-infra/.aptos/chain-b"
NODE_CONFIG="$CHAIN_DIR/0/node.yaml"

echo "🔧 Setting up Chain B..."

# Clean up any existing processes
echo "📋 Cleaning up existing processes..."
pkill -f "aptos-node" || true
pkill -f "aptos node" || true
pkill -f "aptos-faucet-service" || true

# Clean up CLI profiles for fresh start
echo "🧹 Cleaning up CLI profiles..."
aptos config delete-profile --profile alice-chain-b || true
aptos config delete-profile --profile bob-chain-b || true
aptos config delete-profile --profile chain-b || true

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
echo "🔧 Modifying config for ports 8020/8021..."
if [ -f "$NODE_CONFIG" ]; then
    sed -i.bak 's/0.0.0.0:8080/0.0.0.0:8020/g' "$NODE_CONFIG"
    sed -i.bak 's/0.0.0.0:9101/0.0.0.0:9121/g' "$NODE_CONFIG"
    sed -i.bak 's/0.0.0.0:9102/0.0.0.0:9122/g' "$NODE_CONFIG"
    echo "✅ Config modified successfully"
else
    echo "❌ Error: node.yaml not found at $NODE_CONFIG"
    exit 1
fi

# Start Chain B manually
echo "🚀 Starting Chain B on port 8020..."
RUST_LOG=warn testing-infra/external/aptos-core/target/release/aptos-node -f "$NODE_CONFIG" > "$CHAIN_DIR/node.log" 2>&1 &
NODE_PID=$!

# Wait for node to start
echo "⏳ Waiting for Chain B to start..."
sleep 10

# Start Faucet Service
echo "🚰 Starting Faucet Service on port 8021..."
testing-infra/external/aptos-core/target/release/aptos-faucet-service run-simple \
    --node-url http://127.0.0.1:8020 \
    --listen-port 8021 \
    --key-file-path "$CHAIN_DIR/mint.key" \
    --chain-id 5 > "$CHAIN_DIR/faucet.log" 2>&1 &
FAUCET_PID=$!

# Wait for faucet to start
echo "⏳ Waiting for Faucet to start..."
sleep 5

# Test Chain B
echo "🧪 Testing Chain B..."
if curl -s http://127.0.0.1:8020/v1 > /dev/null; then
    echo "✅ Chain B is running successfully!"
    echo "📊 Chain B Status:"
    curl -s http://127.0.0.1:8020/v1 | jq '.chain_id, .block_height, .node_role'
    echo ""
    
    # Test Faucet
    echo "🧪 Testing Faucet..."
    if curl -s http://127.0.0.1:8021/ > /dev/null; then
        echo "✅ Faucet is running successfully!"
    else
        echo "❌ Faucet failed to start"
        kill $FAUCET_PID 2>/dev/null || true
    fi
    
    echo ""
    echo "🔗 Chain B Endpoints:"
    echo "   REST API: http://127.0.0.1:8020"
    echo "   Faucet:   http://127.0.0.1:8021"
    echo ""
    echo "📁 Chain B Directory: $CHAIN_DIR"
    echo "🆔 Node PID: $NODE_PID"
    echo "🆔 Faucet PID: $FAUCET_PID"
    
    # Verify no existing accounts before creating new ones
    echo ""
    echo "🔍 Verifying no existing accounts..."
    EXISTING_PROFILES=$(aptos config show-profiles | jq -r '.Result | keys[]' 2>/dev/null | grep -E "(alice-chain-b|bob-chain-b|chain-b)" || echo "")
    if [ -n "$EXISTING_PROFILES" ]; then
        echo "❌ Error: Found existing Chain B profiles: $EXISTING_PROFILES"
        echo "   Expected: No Chain B profiles should exist on fresh Chain B"
        echo "   Please clean up profiles manually or fix the cleanup process"
        kill $NODE_PID 2>/dev/null || true
        kill $FAUCET_PID 2>/dev/null || true
        exit 1
    else
        echo "✅ No existing Chain B profiles found - proceeding with account creation"
    fi
    
    # Create and fund test accounts
    echo ""
    echo "👥 Creating test accounts..."
    
    # Create alice-chain-b account
    echo "Creating alice-chain-b account..."
    echo "" | aptos init --profile alice-chain-b --network custom --rest-url http://127.0.0.1:8020 --faucet-url http://127.0.0.1:8021 --assume-yes
    
    # Create bob-chain-b account  
    echo "Creating bob-chain-b account..."
    echo "" | aptos init --profile bob-chain-b --network custom --rest-url http://127.0.0.1:8020 --faucet-url http://127.0.0.1:8021 --assume-yes
    
    # Fund both accounts
    echo "Funding accounts..."
    aptos account fund-with-faucet --profile alice-chain-b --amount 100000000
    aptos account fund-with-faucet --profile bob-chain-b --amount 100000000
    
    # Verify balances
    echo ""
    echo "💰 Account Balances:"
    echo "Alice-chain-b balance:"
    aptos account balance --profile alice-chain-b
    echo "Bob-chain-b balance:"
    aptos account balance --profile bob-chain-b
else
    echo "❌ Chain B failed to start"
    kill $NODE_PID 2>/dev/null || true
    kill $FAUCET_PID 2>/dev/null || true
    exit 1
fi

echo "🎉 Chain B setup complete!"
