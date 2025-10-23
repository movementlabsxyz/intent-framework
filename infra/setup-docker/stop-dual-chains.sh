#!/bin/bash

echo "🛑 STOPPING DUAL-CHAIN SETUP"
echo "============================="

echo "🧹 Stopping Chain 1..."
docker-compose -f infra/setup-docker/docker-compose.yml down

echo "🧹 Stopping Chain 2..."
docker-compose -f infra/setup-docker/docker-compose-chain2.yml down

echo ""
echo "✅ Both chains stopped!"
echo "   All containers and volumes cleaned up"
