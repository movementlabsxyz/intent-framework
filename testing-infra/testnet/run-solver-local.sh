#!/bin/bash

# Run Solver Locally (Against Testnets)
#
# This script runs the solver service locally, connecting to:
#   - Local or remote verifier (default: localhost:3333)
#   - Movement Bardock Testnet (hub chain)
#   - Base Sepolia (connected chain)
#
# Use this to test before deploying to EC2.
#
# Prerequisites:
#   - solver/config/solver_testnet.toml configured with actual values
#   - Verifier running (locally or remotely)
#   - Movement CLI profile configured for solver
#   - BASE_SOLVER_PRIVATE_KEY environment variable set
#   - Rust toolchain installed
#
# Usage:
#   ./run-solver-local.sh
#   ./run-solver-local.sh --release  # Run release build (faster)

set -e

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

echo "🔍 Running Solver Locally (Testnet Mode)"
echo "========================================="
echo ""

# Load .testnet-keys.env for BASE_SOLVER_PRIVATE_KEY
TESTNET_KEYS_FILE="$PROJECT_ROOT/.testnet-keys.env"

if [ -f "$TESTNET_KEYS_FILE" ]; then
    source "$TESTNET_KEYS_FILE"
    echo "   Loaded keys from .testnet-keys.env"
fi

# Check BASE_SOLVER_PRIVATE_KEY
if [ -z "$BASE_SOLVER_PRIVATE_KEY" ]; then
    echo "⚠️  WARNING: BASE_SOLVER_PRIVATE_KEY not set"
    echo "   EVM transactions will fail without this."
    echo "   Set it in .testnet-keys.env or export it manually."
    echo ""
fi

# Check config exists
SOLVER_CONFIG="$PROJECT_ROOT/solver/config/solver_testnet.toml"

if [ ! -f "$SOLVER_CONFIG" ]; then
    echo "❌ ERROR: solver_testnet.toml not found at $SOLVER_CONFIG"
    echo ""
    echo "   Create it from the template:"
    echo "   cp solver/config/solver.template.toml solver/config/solver_testnet.toml"
    echo ""
    echo "   Then fill in values from your .testnet-keys.env"
    exit 1
fi

# Validate config doesn't have placeholders
if grep -q "<.*>" "$SOLVER_CONFIG"; then
    echo "❌ ERROR: solver_testnet.toml still has placeholder values (<...>)"
    echo ""
    echo "   Fill in actual values from .testnet-keys.env:"
    echo "   - MOVEMENT_INTENT_MODULE_ADDRESS"
    echo "   - BASE_ESCROW_CONTRACT_ADDRESS"
    echo "   - MOVEMENT_SOLVER_ADDRESS"
    echo "   - EC2_VERIFIER_HOST (or use localhost:3333 for local verifier)"
    exit 1
fi

echo "📋 Configuration:"
echo "   Config file: $SOLVER_CONFIG"
echo ""

# Extract config values for display
VERIFIER_URL=$(grep "verifier_url" "$SOLVER_CONFIG" | sed 's/.*= *"\(.*\)".*/\1/')
HUB_RPC=$(grep -A5 "\[hub_chain\]" "$SOLVER_CONFIG" | grep "rpc_url" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')

echo "   Verifier URL: $VERIFIER_URL"
echo "   Hub Chain RPC: $HUB_RPC"
echo ""

# Check verifier is reachable
echo "   Checking verifier health..."
HEALTH=$(curl -s --max-time 5 "$VERIFIER_URL/health" 2>/dev/null || echo "")

if [ "$HEALTH" = '{"status":"ok"}' ]; then
    echo "   ✅ Verifier is healthy"
else
    echo "   ⚠️  Verifier not responding at $VERIFIER_URL"
    echo ""
    echo "   Make sure verifier is running first:"
    echo "   ./testing-infra/testnet/run-verifier-local.sh"
    echo ""
    read -p "   Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# Check Movement CLI profile exists
SOLVER_PROFILE=$(grep -A5 "\[solver\]" "$SOLVER_CONFIG" | grep "profile" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
if [ -n "$SOLVER_PROFILE" ]; then
    echo "   Checking Movement CLI profile '$SOLVER_PROFILE'..."
    if movement config show-profiles --profile "$SOLVER_PROFILE" &>/dev/null; then
        echo "   ✅ Profile exists"
    else
        echo "   ⚠️  Profile '$SOLVER_PROFILE' not found"
        echo ""
        echo "   Create it with:"
        echo "   movement init --profile $SOLVER_PROFILE \\"
        echo "     --network custom \\"
        echo "     --rest-url https://testnet.movementnetwork.xyz/v1 \\"
        echo "     --private-key \"\$MOVEMENT_SOLVER_PRIVATE_KEY\" \\"
        echo "     --skip-faucet --assume-yes"
        echo ""
        read -p "   Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

echo ""

cd "$PROJECT_ROOT/solver"

# Export private key for EVM transactions
export BASE_SOLVER_PRIVATE_KEY

# Check if --release flag is passed
if [ "$1" = "--release" ]; then
    echo "🔨 Building release binary..."
    cargo build --release
    echo ""
    echo "🚀 Starting solver (release mode)..."
    echo "   Press Ctrl+C to stop"
    echo ""
    SOLVER_CONFIG_PATH="$SOLVER_CONFIG" RUST_LOG=info ./target/release/solver
else
    echo "🚀 Starting solver (debug mode)..."
    echo "   Press Ctrl+C to stop"
    echo "   (Use --release for faster performance)"
    echo ""
    SOLVER_CONFIG_PATH="$SOLVER_CONFIG" RUST_LOG=info cargo run --bin solver
fi

