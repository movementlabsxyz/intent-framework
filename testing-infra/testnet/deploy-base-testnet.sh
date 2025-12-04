#!/bin/bash

# Deploy EVM IntentEscrow to Base Sepolia Testnet
# Reads keys from .testnet-keys.env and deploys the contract

set -e

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
export PROJECT_ROOT

# Source utilities from testing-infra (for CI testing infrastructure)
source "$PROJECT_ROOT/testing-infra/ci-e2e/util.sh" 2>/dev/null || true

echo "🚀 Deploying IntentEscrow to Base Sepolia Testnet"
echo "=================================================="
echo ""

# Load .testnet-keys.env
TESTNET_KEYS_FILE="$PROJECT_ROOT/.testnet-keys.env"

if [ ! -f "$TESTNET_KEYS_FILE" ]; then
    echo "❌ ERROR: .testnet-keys.env not found at $TESTNET_KEYS_FILE"
    echo "   Create it from env.testnet.example first"
    exit 1
fi

# Source the keys file
source "$TESTNET_KEYS_FILE"

# Check required variables
if [ -z "$BASE_DEPLOYER_PRIVATE_KEY" ]; then
    echo "❌ ERROR: BASE_DEPLOYER_PRIVATE_KEY not set in .testnet-keys.env"
    exit 1
fi

if [ -z "$VERIFIER_ETH_ADDRESS" ]; then
    echo "❌ ERROR: VERIFIER_ETH_ADDRESS not set in .testnet-keys.env"
    echo "   Run Phase 1.4 to generate verifier Ethereum address"
    exit 1
fi

echo "📋 Configuration:"
echo "   Deployer Address: $BASE_DEPLOYER_ADDRESS"
echo "   Verifier Address: $VERIFIER_ETH_ADDRESS"
echo "   Network: Base Sepolia"
echo "   RPC URL: https://sepolia.base.org"
echo ""

# Check if Hardhat config exists
if [ ! -f "$PROJECT_ROOT/evm-intent-framework/hardhat.config.js" ]; then
    echo "❌ ERROR: hardhat.config.js not found"
    echo "   Make sure evm-intent-framework directory exists"
    exit 1
fi

# Change to evm-intent-framework directory
cd "$PROJECT_ROOT/evm-intent-framework"

# Export environment variables for Hardhat
export DEPLOYER_PRIVATE_KEY="$BASE_DEPLOYER_PRIVATE_KEY"
export VERIFIER_ADDRESS="$VERIFIER_ETH_ADDRESS"
export BASE_SEPOLIA_RPC_URL="https://sepolia.base.org"

echo "📝 Environment configured for Hardhat"
echo ""

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo "✅ Dependencies installed"
    echo ""
fi

# Deploy contract (run from within nix develop shell)
echo "📤 Deploying IntentEscrow contract..."
echo "   (Run this script from within 'nix develop' shell)"
echo ""
npx hardhat run scripts/deploy.js --network baseSepolia
DEPLOY_EXIT_CODE=$?

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    echo "❌ Deployment failed with exit code $DEPLOY_EXIT_CODE"
    exit 1
fi

echo ""
echo "🎉 Deployment Complete!"
echo "======================"
echo ""
echo "📝 Copy the contract address from the output above"
echo ""
echo "💡 Next steps:"
echo "   1. Update verifier_testnet.toml and solver_testnet.toml with the deployed contract address"
echo "   2. Run ./testing-infra/testnet/check-testnet-preparedness.sh to verify"
echo ""

