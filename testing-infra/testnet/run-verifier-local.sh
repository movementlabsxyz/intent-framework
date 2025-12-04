#!/bin/bash

# Run Verifier Locally (Against Testnets)
#
# This script runs the verifier service locally, connecting to:
#   - Movement Bardock Testnet (hub chain)
#   - Base Sepolia (connected chain)
#
# Use this to test before deploying to EC2.
#
# Prerequisites:
#   - trusted-verifier/config/verifier_testnet.toml configured with actual values
#   - Rust toolchain installed
#
# Usage:
#   ./run-verifier-local.sh
#   ./run-verifier-local.sh --release  # Run release build (faster)

set -e

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

echo "🔍 Running Verifier Locally (Testnet Mode)"
echo "==========================================="
echo ""

# Check config exists
VERIFIER_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testnet.toml"

if [ ! -f "$VERIFIER_CONFIG" ]; then
    echo "❌ ERROR: verifier_testnet.toml not found at $VERIFIER_CONFIG"
    echo ""
    echo "   Create it from the template:"
    echo "   cp trusted-verifier/config/verifier.template.toml trusted-verifier/config/verifier_testnet.toml"
    echo ""
    echo "   Then fill in values from your .testnet-keys.env"
    exit 1
fi

# Load .testnet-keys.env for environment variables
TESTNET_KEYS_FILE="$PROJECT_ROOT/.testnet-keys.env"

if [ ! -f "$TESTNET_KEYS_FILE" ]; then
    echo "❌ ERROR: .testnet-keys.env not found at $TESTNET_KEYS_FILE"
    exit 1
fi

# Source keys file to export environment variables
source "$TESTNET_KEYS_FILE"

# Check required environment variables
REQUIRED_VARS=(
    "VERIFIER_PRIVATE_KEY"
    "VERIFIER_PUBLIC_KEY"
    "MOVEMENT_INTENT_MODULE_ADDRESS"
    "BASE_ESCROW_CONTRACT_ADDRESS"
    "VERIFIER_ETH_ADDRESS"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "❌ ERROR: Missing required environment variables in .testnet-keys.env:"
    for var in "${MISSING_VARS[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

# Validate config doesn't have placeholders (except env var references which are OK)
if grep -q "<MOVEMENT_\|BASE_\|VERIFIER_ETH" "$VERIFIER_CONFIG"; then
    echo "❌ ERROR: verifier_testnet.toml still has placeholder values"
    echo ""
    echo "   Fill in actual values from .testnet-keys.env:"
    echo "   - MOVEMENT_INTENT_MODULE_ADDRESS"
    echo "   - BASE_ESCROW_CONTRACT_ADDRESS"
    echo "   - VERIFIER_ETH_ADDRESS"
    echo "   - MOVEMENT_REQUESTER_ADDRESS, MOVEMENT_SOLVER_ADDRESS (for known_accounts)"
    echo ""
    echo "   Note: VERIFIER_PRIVATE_KEY and VERIFIER_PUBLIC_KEY are loaded from environment variables."
    exit 1
fi

echo "📋 Configuration:"
echo "   Config file: $VERIFIER_CONFIG"
echo ""

# Extract some config values for display
HUB_RPC=$(grep -A5 "\[hub_chain\]" "$VERIFIER_CONFIG" | grep "rpc_url" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
EVM_RPC=$(grep -A5 "\[connected_chain_evm\]" "$VERIFIER_CONFIG" | grep "rpc_url" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
API_PORT=$(grep -A5 "\[api\]" "$VERIFIER_CONFIG" | grep "port" | head -1 | sed 's/.*= *\([0-9]*\).*/\1/')

echo "   Hub Chain RPC: $HUB_RPC"
echo "   EVM Chain RPC: $EVM_RPC"
echo "   API Port: ${API_PORT:-3333}"
echo ""

cd "$PROJECT_ROOT/trusted-verifier"

# Export environment variables for verifier keys
export VERIFIER_PRIVATE_KEY
export VERIFIER_PUBLIC_KEY

# Check if --release flag is passed
if [ "$1" = "--release" ]; then
    echo "🔨 Building release binary..."
    cargo build --release
    echo ""
    echo "🚀 Starting verifier (release mode)..."
    echo "   Press Ctrl+C to stop"
    echo ""
    VERIFIER_CONFIG_PATH="$VERIFIER_CONFIG" RUST_LOG=info ./target/release/trusted-verifier
else
    echo "🚀 Starting verifier (debug mode)..."
    echo "   Press Ctrl+C to stop"
    echo "   (Use --release for faster performance)"
    echo ""
    VERIFIER_CONFIG_PATH="$VERIFIER_CONFIG" RUST_LOG=info cargo run
fi

