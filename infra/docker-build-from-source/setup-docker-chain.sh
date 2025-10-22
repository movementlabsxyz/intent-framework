#!/bin/bash

# Docker Aptos Chain Setup Script
# This script sets up a single Aptos chain in Docker containers

set -e

echo "🐳 DOCKER APTOS CHAIN SETUP"
echo "============================"

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
docker-compose -f infra/docker/docker-compose.yml down 2>/dev/null || true

# Build and start the chain
echo ""
echo "🚀 Building and starting Aptos chain..."
docker-compose -f infra/docker/docker-compose.yml up --build -d

# Wait for services to be ready
echo ""
echo "⏳ Waiting for services to start..."
sleep 30

# Test the chain
echo ""
echo "🧪 Testing Aptos chain..."
if curl -s http://127.0.0.1:8080/v1/ledger/info > /dev/null; then
    echo "✅ Aptos node is running!"
    echo "📊 Chain Status:"
    curl -s http://127.0.0.1:8080/v1/ledger/info | jq '.chain_id, .block_height, .node_role'
    echo ""
    
    # Test faucet
    if curl -s http://127.0.0.1:8081/healthy > /dev/null; then
        echo "✅ Faucet is running!"
    else
        echo "❌ Faucet failed to start"
    fi
    
    echo ""
    echo "🔗 Aptos Chain Endpoints:"
    echo "   REST API: http://127.0.0.1:8080"
    echo "   Faucet:   http://127.0.0.1:8081"
    echo ""
    echo "📁 Docker containers:"
    docker-compose -f infra/docker/docker-compose.yml ps
    echo ""
    echo "🎉 Aptos chain setup complete!"
    echo ""
    echo "To stop the chain: docker-compose -f infra/docker/docker-compose.yml down"
    echo "To view logs: docker-compose -f infra/docker/docker-compose.yml logs -f"
else
    echo "❌ Aptos chain failed to start"
    echo "📋 Container logs:"
    docker-compose -f infra/docker/docker-compose.yml logs
    exit 1
fi
