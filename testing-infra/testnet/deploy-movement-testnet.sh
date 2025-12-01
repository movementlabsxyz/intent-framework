#!/bin/bash

# Deploy Move Intent Framework to Movement Bardock Testnet
# Reads keys from .testnet-keys.env and deploys the Move modules
#
# REQUIRES: Movement CLI (not aptos CLI)
# Install for testnet (Move 2 support):
#   ARM64: curl -LO https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-macos-arm64.tar.gz && mkdir -p temp_extract && tar -xzf movement-move2-testnet-macos-arm64.tar.gz -C temp_extract && chmod +x temp_extract/movement && sudo mv temp_extract/movement /usr/local/bin/movement && rm -rf temp_extract
#   x86_64: curl -LO https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-macos-x86_64.tar.gz && mkdir -p temp_extract && tar -xzf movement-move2-testnet-macos-x86_64.tar.gz -C temp_extract && chmod +x temp_extract/movement && sudo mv temp_extract/movement /usr/local/bin/movement && rm -rf temp_extract
#
# Reference: https://docs.movementnetwork.xyz/devs/movementcli

set -e

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
export PROJECT_ROOT

echo "🚀 Deploying Move Intent Framework to Movement Bardock Testnet"
echo "=============================================================="
echo ""

# Check for movement CLI
if ! command -v movement &> /dev/null; then
    echo "❌ ERROR: movement CLI not found"
    echo ""
    echo "   Movement testnet requires the Movement CLI (not aptos CLI)."
    echo "   Install the Move 2 testnet CLI:"
    echo ""
    echo "   # For Mac ARM64 (M-series):"
    echo "   curl -LO https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-macos-arm64.tar.gz && mkdir -p temp_extract && tar -xzf movement-move2-testnet-macos-arm64.tar.gz -C temp_extract && chmod +x temp_extract/movement && sudo mv temp_extract/movement /usr/local/bin/movement && rm -rf temp_extract"
    echo ""
    echo "   # For Mac Intel (x86_64):"
    echo "   curl -LO https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-macos-x86_64.tar.gz && mkdir -p temp_extract && tar -xzf movement-move2-testnet-macos-x86_64.tar.gz -C temp_extract && chmod +x temp_extract/movement && sudo mv temp_extract/movement /usr/local/bin/movement && rm -rf temp_extract"
    echo ""
    echo "   Reference: https://docs.movementnetwork.xyz/devs/movementcli"
    exit 1
fi

echo "✅ Movement CLI found: $(movement --version)"
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
if [ -z "$MOVEMENT_DEPLOYER_PRIVATE_KEY" ]; then
    echo "❌ ERROR: MOVEMENT_DEPLOYER_PRIVATE_KEY not set in .testnet-keys.env"
    exit 1
fi

if [ -z "$MOVEMENT_DEPLOYER_ADDRESS" ]; then
    echo "❌ ERROR: MOVEMENT_DEPLOYER_ADDRESS not set in .testnet-keys.env"
    exit 1
fi

# Remove 0x prefix from address if present
DEPLOYER_ADDRESS="${MOVEMENT_DEPLOYER_ADDRESS#0x}"
DEPLOYER_ADDRESS_FULL="0x${DEPLOYER_ADDRESS}"

echo "📋 Configuration:"
echo "   Deployer Address: $DEPLOYER_ADDRESS_FULL"
echo "   Network: Movement Bardock Testnet"
echo "   RPC URL: https://testnet.movementnetwork.xyz/v1"
echo ""

# Configure Movement CLI profile
echo "🔧 Step 1: Configuring Movement CLI profile..."

# Initialize Movement profile for Bardock (skip funding - account should already be funded)
movement init --profile movement-testnet \
  --network custom \
  --rest-url https://testnet.movementnetwork.xyz/v1 \
  --faucet-url https://faucet.movementnetwork.xyz/ \
  --private-key "$MOVEMENT_DEPLOYER_PRIVATE_KEY" \
  --skip-faucet \
  --assume-yes

echo "✅ Movement CLI profile configured"
echo ""

# Compile Move modules
echo "🔨 Step 2: Compiling Move modules..."
cd "$PROJECT_ROOT/move-intent-framework"

movement move compile \
  --named-addresses mvmt_intent="$DEPLOYER_ADDRESS_FULL" \
  --skip-fetch-latest-git-deps

echo "✅ Compilation successful"
echo ""

# Deploy Move modules
echo "📤 Step 3: Deploying Move modules to Movement Bardock Testnet..."

movement move publish \
  --profile movement-testnet \
  --named-addresses mvmt_intent="$DEPLOYER_ADDRESS_FULL" \
  --skip-fetch-latest-git-deps \
  --assume-yes

echo "✅ Deployment successful"
echo ""

# Verify deployment
echo "🔍 Step 4: Verifying deployment..."

# Try to call a view function to verify modules are deployed
movement move view \
  --profile movement-testnet \
  --function-id "${DEPLOYER_ADDRESS_FULL}::intent::get_intent_count" \
  --args "address:$DEPLOYER_ADDRESS_FULL" || {
    echo "⚠️  Warning: Could not verify deployment via view function"
    echo "   This may be normal if the function doesn't exist yet"
  }

echo "✅ Verification complete"
echo ""

echo "🎉 Deployment Complete!"
echo "======================"
echo ""
echo "📝 Save this address to your .testnet-keys.env:"
echo "   MOVEMENT_INTENT_MODULE_ADDRESS=$DEPLOYER_ADDRESS_FULL"
echo ""
echo "💡 Next steps:"
echo "   1. Update .testnet-keys.env with MOVEMENT_INTENT_MODULE_ADDRESS"
echo "   2. Proceed to Phase 3: Deploy EVM IntentEscrow to Base Sepolia"
echo ""
