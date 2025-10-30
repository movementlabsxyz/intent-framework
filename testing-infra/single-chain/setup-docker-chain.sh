#!/bin/bash

# Docker Aptos Localnet Setup Script
# This script sets up a complete Aptos localnet in Docker with all services

set -e

echo "🐳 DOCKER APTOS LOCALNET SETUP"
echo "==============================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running"
    echo "Please start Docker Desktop and try again"
    exit 1
fi

echo "✅ Docker is running"

# Stop any existing containers
echo ""
echo "🧹 Stopping existing containers..."
docker-compose -f infra/setup-docker/docker-compose.yml down 2>/dev/null || true

# Build and start the localnet
echo ""
echo "🚀 Starting Aptos localnet with all services..."
docker-compose -f infra/setup-docker/docker-compose.yml up -d

# Wait for services to be ready
echo ""
echo "⏳ Waiting for services to start (this may take 1-2 minutes)..."
echo "   - Node API starting..."
echo "   - Faucet starting..."

# Wait for readiness endpoint
echo ""
echo "🔍 Checking service readiness..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8070/ > /dev/null 2>&1; then
        echo "✅ All services are ready!"
        break
    fi
    echo "   Waiting... (attempt $i/30)"
    sleep 10
done

# Test the services
echo ""
echo "🧪 Testing Aptos localnet services..."

# Test Node API
if curl -s http://127.0.0.1:8080/v1/ledger/info > /dev/null; then
    echo "✅ Node API is running!"
    echo "📊 Chain Status:"
    curl -s http://127.0.0.1:8080/v1/ledger/info | jq '.chain_id, .block_height, .node_role' 2>/dev/null || echo "   Chain ID: $(curl -s http://127.0.0.1:8080/v1/ledger/info | grep -o '"chain_id":[0-9]*' | cut -d: -f2)"
else
    echo "❌ Node API failed to start"
fi

# Test Faucet
if curl -s http://127.0.0.1:8081/healthy > /dev/null; then
    echo "✅ Faucet is running!"
else
    echo "❌ Faucet failed to start"
fi

# Test Indexer API
if curl -s http://127.0.0.1:8090/health > /dev/null; then
    echo "✅ Indexer API is running!"
else
    echo "ℹ️  Indexer API not available (running with faucet only)"
fi

echo ""
echo "🔗 Aptos Localnet Endpoints:"
echo "   REST API:        http://127.0.0.1:8080"
echo "   Faucet:          http://127.0.0.1:8081"
echo ""
echo "ℹ️  Note: Running with faucet only (no Indexer API) for simplicity"
echo ""
echo "📁 Docker containers:"
docker-compose -f infra/setup-docker/docker-compose.yml ps
echo ""
echo "🎉 Aptos localnet setup complete!"
echo ""
echo "🔄 Fresh start every time:"
echo "   Each run starts from block 0 with clean state"
echo "   All previous accounts and transactions are cleared"
echo ""
echo "📋 Management Commands:"
echo "   Stop:    docker-compose -f infra/setup-docker/docker-compose.yml down"
echo "   Logs:    docker-compose -f infra/setup-docker/docker-compose.yml logs -f"
echo "   Restart: docker-compose -f infra/setup-docker/docker-compose.yml restart"
