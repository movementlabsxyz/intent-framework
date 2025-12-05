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
#   - trusted-verifier/config/verifier_testnet.toml configured with actual deployed addresses
#   - .testnet-keys.env with VERIFIER_PRIVATE_KEY and VERIFIER_PUBLIC_KEY
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
    echo "   Then populate with actual deployed contract addresses:"
    echo "   - intent_module_address (hub_chain section)"
    echo "   - escrow_contract_address (connected_chain_evm section)"
    echo "   - verifier_address (connected_chain_evm section)"
    echo "   - known_accounts (hub_chain section)"
    exit 1
fi

# Load .testnet-keys.env for environment variables
TESTNET_KEYS_FILE="$PROJECT_ROOT/.testnet-keys.env"

if [ ! -f "$TESTNET_KEYS_FILE" ]; then
    echo "❌ ERROR: .testnet-keys.env not found at $TESTNET_KEYS_FILE"
    echo ""
    echo "   Create it from the template:"
    echo "   cp env.testnet.example .testnet-keys.env"
    echo ""
    echo "   Then populate with your testnet keys."
    exit 1
fi

# Source keys file to export environment variables
source "$TESTNET_KEYS_FILE"

# Check required environment variables (keys only)
REQUIRED_VARS=(
    "VERIFIER_PRIVATE_KEY"
    "VERIFIER_PUBLIC_KEY"
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
    echo ""
    echo "   These keys are required for the verifier to sign approvals."
    exit 1
fi

# Validate config has actual addresses (not placeholders)
# Check for common placeholder patterns
if grep -qE "(0x123|0x\.\.\.|0xalice|0xbob)" "$VERIFIER_CONFIG"; then
    echo "❌ ERROR: verifier_testnet.toml still has placeholder addresses"
    echo ""
    echo "   Update the config file with actual deployed addresses:"
    echo "   - intent_module_address (hub_chain section)"
    echo "   - escrow_contract_address (connected_chain_evm section)"
    echo "   - verifier_address (connected_chain_evm section)"
    echo "   - known_accounts (hub_chain section)"
    echo ""
    echo "   Contract addresses should be read from your deployment logs."
    exit 1
fi

# Extract config values for display
HUB_RPC=$(grep -A5 "\[hub_chain\]" "$VERIFIER_CONFIG" | grep "rpc_url" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
EVM_RPC=$(grep -A5 "\[connected_chain_evm\]" "$VERIFIER_CONFIG" | grep "rpc_url" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
API_PORT=$(grep -A5 "\[api\]" "$VERIFIER_CONFIG" | grep "port" | head -1 | sed 's/.*= *\([0-9]*\).*/\1/')
INTENT_MODULE=$(grep -A5 "\[hub_chain\]" "$VERIFIER_CONFIG" | grep "intent_module_address" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
ESCROW_CONTRACT=$(grep -A5 "\[connected_chain_evm\]" "$VERIFIER_CONFIG" | grep "escrow_contract_address" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')

# Check for API key placeholders in RPC URLs
if [[ "$HUB_RPC" == *"ALCHEMY_API_KEY"* ]] || [[ "$EVM_RPC" == *"ALCHEMY_API_KEY"* ]]; then
    echo "⚠️  WARNING: RPC URLs contain API key placeholders (ALCHEMY_API_KEY)"
    echo "   The verifier service does not substitute placeholders - use full URLs in config"
    echo "   Or use the public RPC URLs from testnet-assets.toml"
    echo ""
fi

echo "📋 Configuration:"
echo "   Config file: $VERIFIER_CONFIG"
echo "   Keys file:   $TESTNET_KEYS_FILE"
echo ""
echo "   Hub Chain:"
echo "     RPC:              $HUB_RPC"
echo "     Intent Module:     $INTENT_MODULE"
echo ""
echo "   EVM Chain:"
echo "     RPC:              $EVM_RPC"
echo "     Escrow Contract:  $ESCROW_CONTRACT"
echo ""
echo "   API Server:"
echo "     Port:             ${API_PORT:-3333}"
echo ""

cd "$PROJECT_ROOT/trusted-verifier"

# Export environment variables for verifier keys
export VERIFIER_PRIVATE_KEY
export VERIFIER_PUBLIC_KEY

# Check if --release flag is passed
if [ "$1" = "--release" ]; then
    echo "🔨 Building release binary..."
    nix develop --command bash -c "cd '$PROJECT_ROOT/trusted-verifier' && cargo build --release"
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
    nix develop --command bash -c "cd '$PROJECT_ROOT/trusted-verifier' && VERIFIER_CONFIG_PATH='$VERIFIER_CONFIG' RUST_LOG=info cargo run --bin trusted-verifier"
fi

