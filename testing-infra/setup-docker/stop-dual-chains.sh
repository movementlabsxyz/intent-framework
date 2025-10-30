#!/bin/bash

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

cd "$PROJECT_ROOT"

echo "🛑 STOPPING DUAL-CHAIN SETUP"
echo "============================="

echo "🧹 Stopping Chain 1..."
docker-compose -f testing-infra/setup-docker/docker-compose.yml -p aptos-chain1 down

echo "🧹 Stopping Chain 2..."
docker-compose -f testing-infra/setup-docker/docker-compose-chain2.yml -p aptos-chain2 down

echo ""
echo "🧹 Cleaning up Aptos CLI profiles..."
aptos config delete-profile --profile alice-chain1 2>/dev/null || true
aptos config delete-profile --profile bob-chain1 2>/dev/null || true
aptos config delete-profile --profile alice-chain2 2>/dev/null || true
aptos config delete-profile --profile bob-chain2 2>/dev/null || true
aptos config delete-profile --profile intent-account-chain1 2>/dev/null || true
aptos config delete-profile --profile intent-account-chain2 2>/dev/null || true

echo ""
echo "✅ Both chains stopped!"
echo "   All containers, volumes, and CLI profiles cleaned up"
