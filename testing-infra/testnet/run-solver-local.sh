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
#   - solver/config/solver_testnet.toml configured with actual deployed addresses
#   - .testnet-keys.env with BASE_SOLVER_PRIVATE_KEY
#   - Movement CLI profile configured for solver (uses MOVEMENT_SOLVER_PRIVATE_KEY from .testnet-keys.env)
#   - Verifier running (locally or remotely)
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

if [ ! -f "$TESTNET_KEYS_FILE" ]; then
    echo "❌ ERROR: .testnet-keys.env not found at $TESTNET_KEYS_FILE"
    echo ""
    echo "   Create it from the template:"
    echo "   cp env.testnet.example .testnet-keys.env"
    echo ""
    echo "   Then populate with your testnet keys."
    exit 1
fi

source "$TESTNET_KEYS_FILE"

# Check BASE_SOLVER_PRIVATE_KEY (required for EVM transactions)
if [ -z "$BASE_SOLVER_PRIVATE_KEY" ]; then
    echo "❌ ERROR: BASE_SOLVER_PRIVATE_KEY not set in .testnet-keys.env"
    echo ""
    echo "   This key is required for EVM transactions on Base Sepolia."
    echo "   Add it to .testnet-keys.env"
    exit 1
fi

# Check config exists
SOLVER_CONFIG="$PROJECT_ROOT/solver/config/solver_testnet.toml"

if [ ! -f "$SOLVER_CONFIG" ]; then
    echo "❌ ERROR: solver_testnet.toml not found at $SOLVER_CONFIG"
    echo ""
    echo "   Create it from the template:"
    echo "   cp solver/config/solver.template.toml solver/config/solver_testnet.toml"
    echo ""
    echo "   Then populate with actual deployed contract addresses:"
    echo "   - module_address (hub_chain section)"
    echo "   - escrow_contract_address (connected_chain section)"
    echo "   - address (solver section)"
    echo "   - verifier_url (service section - use localhost:3333 for local testing)"
    exit 1
fi

# Validate config has actual addresses (not placeholders)
# Check for common placeholder patterns
if grep -qE "(0x123|0x\.\.\.|0x\.\.\.)" "$SOLVER_CONFIG"; then
    echo "❌ ERROR: solver_testnet.toml still has placeholder addresses"
    echo ""
    echo "   Update the config file with actual deployed addresses:"
    echo "   - module_address (hub_chain section)"
    echo "   - escrow_contract_address (connected_chain section)"
    echo "   - address (solver section)"
    echo "   - verifier_url (service section - use localhost:3333 for local testing)"
    echo ""
    echo "   Contract addresses should be read from your deployment logs."
    exit 1
fi

# Extract config values for display (skip comment lines)
VERIFIER_URL=$(grep "^verifier_url" "$SOLVER_CONFIG" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)
HUB_RPC=$(grep -A5 "\[hub_chain\]" "$SOLVER_CONFIG" | grep "^rpc_url" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)
HUB_MODULE=$(grep -A5 "\[hub_chain\]" "$SOLVER_CONFIG" | grep "^module_address" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)
SOLVER_PROFILE=$(grep -A5 "\[solver\]" "$SOLVER_CONFIG" | grep "^profile" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)
SOLVER_ADDRESS=$(grep -A5 "\[solver\]" "$SOLVER_CONFIG" | grep "^address" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)

# Check if connected chain is EVM and extract escrow address
CONNECTED_TYPE=$(grep -A2 "\[connected_chain\]" "$SOLVER_CONFIG" | grep "^type" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)
if [ "$CONNECTED_TYPE" = "evm" ]; then
    ESCROW_CONTRACT=$(grep -A5 "\[connected_chain\]" "$SOLVER_CONFIG" | grep "^escrow_contract_address" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)
    CONNECTED_RPC=$(grep -A5 "\[connected_chain\]" "$SOLVER_CONFIG" | grep "^rpc_url" | grep -v "^#" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' | sed 's/#.*$//' | xargs)
fi

# Check for API key placeholders in RPC URLs
if [[ "$HUB_RPC" == *"ALCHEMY_API_KEY"* ]] || ([ "$CONNECTED_TYPE" = "evm" ] && [[ "$CONNECTED_RPC" == *"ALCHEMY_API_KEY"* ]]); then
    echo "⚠️  WARNING: RPC URLs contain API key placeholders (ALCHEMY_API_KEY)"
    echo "   The solver service does not substitute placeholders - use full URLs in config"
    echo "   Or use the public RPC URLs from testnet-assets.toml"
    echo ""
fi

echo "📋 Configuration:"
echo "   Config file: $SOLVER_CONFIG"
echo "   Keys file:   $TESTNET_KEYS_FILE"
echo ""
echo "   Verifier:"
echo "     URL:              $VERIFIER_URL"
echo ""
echo "   Hub Chain:"
echo "     RPC:              $HUB_RPC"
echo "     Module Address:    $HUB_MODULE"
echo ""
if [ "$CONNECTED_TYPE" = "evm" ]; then
    echo "   Connected Chain (EVM):"
    echo "     Escrow Contract:  $ESCROW_CONTRACT"
    echo ""
fi
echo "   Solver:"
echo "     Profile:          $SOLVER_PROFILE"
echo "     Address:          $SOLVER_ADDRESS"
echo ""

# Check verifier is reachable
echo "   Checking verifier health..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$VERIFIER_URL/health" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ Verifier is healthy"
else
    echo "   ⚠️  Verifier not responding at $VERIFIER_URL (HTTP $HTTP_CODE)"
    echo ""
    echo "   Make sure verifier is running first:"
    echo "   ./testing-infra/testnet/run-verifier-local.sh"
    echo ""
    echo "   Quick check: curl $VERIFIER_URL/health"
    echo ""
    read -p "   Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# Check Movement CLI profile exists
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
        echo "   Note: MOVEMENT_SOLVER_PRIVATE_KEY should be set in .testnet-keys.env"
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

# Export environment variables for solver (needed for nix develop subprocess)
export BASE_SOLVER_PRIVATE_KEY
# Export solver addresses for auto-registration (solver reads BASE_SOLVER_ADDRESS or SOLVER_EVM_ADDRESS)
export BASE_SOLVER_ADDRESS
export SOLVER_EVM_ADDRESS  # May be empty, that's OK
# Export Movement solver private key for registration (solver reads from env var first, then profile)
if [ -n "$MOVEMENT_SOLVER_PRIVATE_KEY" ]; then
    export MOVEMENT_SOLVER_PRIVATE_KEY
fi

# Export HUB_RPC_URL for hash calculation
export HUB_RPC_URL="$HUB_RPC"

# Prepare environment variables for nix develop
# Use debug logging for tracker and hub client to see intent detection
ENV_VARS="SOLVER_CONFIG_PATH='$SOLVER_CONFIG' RUST_LOG=info,solver::service::tracker=debug,solver::chains::hub=debug HUB_RPC_URL='$HUB_RPC'"
if [ -n "$BASE_SOLVER_PRIVATE_KEY" ]; then
    ENV_VARS="$ENV_VARS BASE_SOLVER_PRIVATE_KEY='$BASE_SOLVER_PRIVATE_KEY'"
fi
if [ -n "$BASE_SOLVER_ADDRESS" ]; then
    ENV_VARS="$ENV_VARS BASE_SOLVER_ADDRESS='$BASE_SOLVER_ADDRESS'"
fi
if [ -n "$SOLVER_EVM_ADDRESS" ]; then
    ENV_VARS="$ENV_VARS SOLVER_EVM_ADDRESS='$SOLVER_EVM_ADDRESS'"
fi
if [ -n "$MOVEMENT_SOLVER_PRIVATE_KEY" ]; then
    ENV_VARS="$ENV_VARS MOVEMENT_SOLVER_PRIVATE_KEY='$MOVEMENT_SOLVER_PRIVATE_KEY'"
fi

# Check if --release flag is passed
if [ "$1" = "--release" ]; then
    echo "🔨 Building release binary..."
    nix develop --command bash -c "cd '$PROJECT_ROOT/solver' && cargo build --release"
    echo ""
    echo "🚀 Starting solver (release mode)..."
    echo "   Press Ctrl+C to stop"
    echo ""
    eval "$ENV_VARS ./target/release/solver"
else
    echo "🚀 Starting solver (debug mode)..."
    echo "   Press Ctrl+C to stop"
    echo "   (Use --release for faster performance)"
    echo ""
    nix develop --command bash -c "cd '$PROJECT_ROOT/solver' && $ENV_VARS cargo run --bin solver"
fi

