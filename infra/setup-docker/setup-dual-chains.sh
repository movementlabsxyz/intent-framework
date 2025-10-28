#!/bin/bash

echo "🔗 DUAL-CHAIN APTOS SETUP"
echo "=========================="

# Stop any existing containers
echo "🧹 Stopping existing containers..."
docker-compose -f infra/setup-docker/docker-compose.yml -p aptos-chain1 down 2>/dev/null || true
docker-compose -f infra/setup-docker/docker-compose-chain2.yml -p aptos-chain2 down 2>/dev/null || true

echo ""
echo "🚀 Starting Chain 1 (ports 8080/8081)..."
docker-compose -f infra/setup-docker/docker-compose.yml -p aptos-chain1 up -d

echo ""
echo "🚀 Starting Chain 2 (ports 8082/8083)..."
docker-compose -f infra/setup-docker/docker-compose-chain2.yml -p aptos-chain2 up -d

echo ""
echo "⏳ Waiting for both chains to start (this may take 2-3 minutes)..."

# Wait for Chain 1
echo "   - Waiting for Chain 1 services..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8080/v1/ledger/info >/dev/null 2>&1 && curl -s http://127.0.0.1:8081/ >/dev/null 2>&1; then
        echo "   ✅ Chain 1 ready!"
        break
    fi
    echo "   Waiting... (attempt $i/30)"
    sleep 5
done

# Wait for Chain 2
echo "   - Waiting for Chain 2 services..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8082/v1/ledger/info >/dev/null 2>&1 && curl -s http://127.0.0.1:8083/ >/dev/null 2>&1; then
        echo "   ✅ Chain 2 ready!"
        break
    fi
    echo "   Waiting... (attempt $i/30)"
    sleep 5
done

echo ""
echo "🔍 Verifying both chains..."

# Check Chain 1
CHAIN1_INFO=$(curl -s http://127.0.0.1:8080/v1/ledger/info 2>/dev/null || echo "null")
if [ "$CHAIN1_INFO" != "null" ]; then
    CHAIN1_ID=$(echo "$CHAIN1_INFO" | jq -r '.chain_id // "unknown"')
    CHAIN1_HEIGHT=$(echo "$CHAIN1_INFO" | jq -r '.block_height // "unknown"')
    echo "✅ Chain 1: ID=$CHAIN1_ID, Height=$CHAIN1_HEIGHT"
else
    echo "❌ Chain 1 failed to start"
    exit 1
fi

# Check Chain 2
CHAIN2_INFO=$(curl -s http://127.0.0.1:8082/v1/ledger/info 2>/dev/null || echo "null")
if [ "$CHAIN2_INFO" != "null" ]; then
    CHAIN2_ID=$(echo "$CHAIN2_INFO" | jq -r '.chain_id // "unknown"')
    CHAIN2_HEIGHT=$(echo "$CHAIN2_INFO" | jq -r '.block_height // "unknown"')
    echo "✅ Chain 2: ID=$CHAIN2_ID, Height=$CHAIN2_HEIGHT"
else
    echo "❌ Chain 2 failed to start"
    exit 1
fi

echo ""
echo "🔗 Dual-Chain Endpoints:"
echo "   Chain 1:"
echo "     REST API:        http://127.0.0.1:8080"
echo "     Faucet:          http://127.0.0.1:8081"
echo "   Chain 2:"
echo "     REST API:        http://127.0.0.1:8082"
echo "     Faucet:          http://127.0.0.1:8083"

echo ""
echo "📋 Management Commands:"
echo "   Stop Chain 1:    docker-compose -f infra/setup-docker/docker-compose.yml -p aptos-chain1 down"
echo "   Stop Chain 2:    docker-compose -f infra/setup-docker/docker-compose-chain2.yml -p aptos-chain2 down"
echo "   Stop Both:       ./infra/setup-docker/stop-dual-chains.sh"
echo "   Logs Chain 1:    docker-compose -f infra/setup-docker/docker-compose.yml -p aptos-chain1 logs -f"
echo "   Logs Chain 2:    docker-compose -f infra/setup-docker/docker-compose-chain2.yml -p aptos-chain2 logs -f"

echo ""
echo "🎉 Dual-chain setup complete!"
echo "   Both chains are running independently with different chain IDs"
echo "   Ready for cross-chain testing!"
