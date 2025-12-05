#!/bin/bash

# Deploy Move Intent Framework to Movement Bardock Testnet
#
# This script generates a FRESH address for each deployment to avoid
# backward-incompatible module update errors. Funds are transferred from
# the deployer account in .testnet-keys.env to the new module address.
#
# The new module address must be updated in verifier and solver config
# files after deployment.
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

# Load .testnet-keys.env for the funding account
TESTNET_KEYS_FILE="$PROJECT_ROOT/.testnet-keys.env"

if [ ! -f "$TESTNET_KEYS_FILE" ]; then
    echo "❌ ERROR: .testnet-keys.env not found at $TESTNET_KEYS_FILE"
    echo "   Create it from env.testnet.example first"
    exit 1
fi

source "$TESTNET_KEYS_FILE"

# Check required variables for funding account
if [ -z "$MOVEMENT_DEPLOYER_PRIVATE_KEY" ]; then
    echo "❌ ERROR: MOVEMENT_DEPLOYER_PRIVATE_KEY not set in .testnet-keys.env"
    exit 1
fi

if [ -z "$MOVEMENT_DEPLOYER_ADDRESS" ]; then
    echo "❌ ERROR: MOVEMENT_DEPLOYER_ADDRESS not set in .testnet-keys.env"
    exit 1
fi

FUNDER_ADDRESS="${MOVEMENT_DEPLOYER_ADDRESS#0x}"
FUNDER_ADDRESS_FULL="0x${FUNDER_ADDRESS}"

# Setup funding account profile
echo "🔧 Step 1: Setting up funding account..."
movement init --profile movement-funder \
  --network custom \
  --rest-url https://testnet.movementnetwork.xyz/v1 \
  --faucet-url https://faucet.movementnetwork.xyz/ \
  --private-key "$MOVEMENT_DEPLOYER_PRIVATE_KEY" \
  --skip-faucet \
  --assume-yes 2>/dev/null

echo "   Funder address: $FUNDER_ADDRESS_FULL"
echo ""

# Generate a fresh key pair for module deployment
echo "🔑 Step 2: Generating fresh module address..."

# Create temp directory for key generation
TEMP_DIR=$(mktemp -d)
KEY_FILE="$TEMP_DIR/deploy_key"

# Generate a new Ed25519 key pair
movement key generate --key-type ed25519 --output-file "$KEY_FILE" --assume-yes 2>/dev/null

# Read the private key from the generated file
DEPLOY_PRIVATE_KEY=$(cat "${KEY_FILE}.key" 2>/dev/null || cat "$KEY_FILE" 2>/dev/null)

# Initialize a temporary profile to get the address
TEMP_PROFILE="movement-deploy-temp-$$"
movement init --profile "$TEMP_PROFILE" \
  --network custom \
  --rest-url https://testnet.movementnetwork.xyz/v1 \
  --faucet-url https://faucet.movementnetwork.xyz/ \
  --private-key "$DEPLOY_PRIVATE_KEY" \
  --skip-faucet \
  --assume-yes 2>/dev/null

# Extract the address from the profile
DEPLOY_ADDRESS=$(movement config show-profiles --profile "$TEMP_PROFILE" 2>/dev/null | jq -r ".Result.\"$TEMP_PROFILE\".account // empty" || echo "")

if [ -z "$DEPLOY_ADDRESS" ]; then
    echo "❌ ERROR: Failed to extract address from generated key"
    rm -rf "$TEMP_DIR"
    exit 1
fi

DEPLOY_ADDRESS_FULL="0x${DEPLOY_ADDRESS}"
echo "   Module address: $DEPLOY_ADDRESS_FULL"
echo ""

# Fund the new address - try faucet first, fall back to transfer from deployer
echo "💰 Step 3: Funding module address..."

FUND_AMOUNT=100000000  # 1 MOVE in octas
FAUCET_SUCCESS=false

# Try faucet via curl (Movement testnet faucet API)
echo "   Trying faucet..."
FAUCET_RESPONSE=$(curl -s -X POST "https://faucet.movementnetwork.xyz/mint?amount=$FUND_AMOUNT&address=$DEPLOY_ADDRESS_FULL" 2>/dev/null || echo "")

if [ -n "$FAUCET_RESPONSE" ] && ! echo "$FAUCET_RESPONSE" | grep -qi "error"; then
    echo "   ✅ Faucet request sent"
    FAUCET_SUCCESS=true
    sleep 3  # Wait for faucet transaction
else
    # Try alternative faucet method via CLI
    if movement account fund-with-faucet \
        --profile "$TEMP_PROFILE" \
        --faucet-url https://faucet.movementnetwork.xyz/ \
        --amount $FUND_AMOUNT 2>/dev/null; then
        echo "   ✅ Faucet funding successful"
        FAUCET_SUCCESS=true
    fi
fi

# Check if funding worked
if [ "$FAUCET_SUCCESS" = true ]; then
    sleep 2
    BALANCE=$(curl -s "https://testnet.movementnetwork.xyz/v1/accounts/$DEPLOY_ADDRESS_FULL/resources" 2>/dev/null | jq -r '.[] | select(.type == "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") | .data.coin.value // "0"' || echo "0")
    if [ "$BALANCE" = "0" ] || [ -z "$BALANCE" ]; then
        echo "   ⚠️  Faucet didn't fund the account"
        FAUCET_SUCCESS=false
    fi
fi

# If faucet failed, offer options
if [ "$FAUCET_SUCCESS" = false ]; then
    echo ""
    echo "   Faucet unavailable or failed."
    echo "   Module address: $DEPLOY_ADDRESS_FULL"
    echo ""
    echo "   Options:"
    echo "   [y] Transfer 1 MOVE from your deployer account ($FUNDER_ADDRESS_FULL)"
    echo "   [m] Manually fund via https://faucet.movementlabs.xyz (then press Enter)"
    echo "   [n] Cancel deployment"
    echo ""
    read -p "   Choice (y/m/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Transferring from deployer account..."
        movement move run \
          --profile movement-funder \
          --function-id "0x1::aptos_account::transfer" \
          --args "address:$DEPLOY_ADDRESS_FULL" "u64:$FUND_AMOUNT" \
          --assume-yes
        echo "   ✅ Transferred $FUND_AMOUNT octas (1 MOVE) from deployer"
    elif [[ $REPLY =~ ^[Mm]$ ]]; then
        echo ""
        echo "   Please fund this address manually:"
        echo "   $DEPLOY_ADDRESS_FULL"
        echo ""
        echo "   Visit: https://faucet.movementlabs.xyz"
        echo ""
        read -p "   Press Enter when funded..." -r
    else
        echo "   ❌ Deployment cancelled"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# Wait for transaction to propagate
sleep 3

# Verify balance with retry option
while true; do
    echo "   Verifying balance..."
    BALANCE=$(curl -s "https://testnet.movementnetwork.xyz/v1/accounts/$DEPLOY_ADDRESS_FULL/resources" 2>/dev/null | jq -r '.[] | select(.type == "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") | .data.coin.value // "0"' || echo "0")
    if [ -z "$BALANCE" ]; then BALANCE="0"; fi
    echo "   Module address balance: $BALANCE octas"
    
    if [ "$BALANCE" != "0" ] && [ -n "$BALANCE" ]; then
        echo "   ✅ Module address funded"
        break
    fi
    
    echo ""
    echo "⚠️  Balance is still 0."
    echo "   [r] Retry balance check"
    echo "   [y] Continue anyway (deployment may fail)"
    echo "   [n] Cancel deployment"
    read -p "   Choice (r/y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Rr]$ ]]; then
        echo "   Waiting 3 seconds before retry..."
        sleep 3
        continue
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Continuing with 0 balance..."
        break
    else
        echo "   ❌ Deployment cancelled"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
done
echo ""

echo "📋 Configuration:"
echo "   Funder Address: $FUNDER_ADDRESS_FULL"
echo "   Module Address: $DEPLOY_ADDRESS_FULL"
echo "   Network: Movement Bardock Testnet"
echo "   RPC URL: https://testnet.movementnetwork.xyz/v1"
echo ""

# Compile Move modules
echo "🔨 Step 4: Compiling Move modules..."
cd "$PROJECT_ROOT/move-intent-framework"

movement move compile \
  --named-addresses mvmt_intent="$DEPLOY_ADDRESS_FULL" \
  --skip-fetch-latest-git-deps

echo "✅ Compilation successful"
echo ""

# Deploy Move modules
echo "📤 Step 5: Deploying Move modules to Movement Bardock Testnet..."

movement move publish \
  --profile "$TEMP_PROFILE" \
  --named-addresses mvmt_intent="$DEPLOY_ADDRESS_FULL" \
  --skip-fetch-latest-git-deps \
  --assume-yes

echo "✅ Deployment successful"
echo ""

# Verify deployment by calling a view function
echo "🔍 Step 6: Verifying deployment..."

movement move view \
  --profile "$TEMP_PROFILE" \
  --function-id "${DEPLOY_ADDRESS_FULL}::solver_registry::is_registered" \
  --args "address:$DEPLOY_ADDRESS_FULL" && {
    echo "   ✅ View function works - module deployed correctly with #[view] attribute"
  } || {
    echo "   ⚠️  Warning: View function verification failed"
    echo "   This may indicate the module wasn't deployed correctly"
  }

echo ""

# Initialize solver registry
echo "🔧 Step 7: Initializing solver registry..."

movement move run \
  --profile "$TEMP_PROFILE" \
  --function-id "${DEPLOY_ADDRESS_FULL}::solver_registry::initialize" \
  --assume-yes 2>/dev/null && {
    echo "   ✅ Solver registry initialized"
  } || {
    echo "   ⚠️  Solver registry may already be initialized (this is OK)"
  }

echo ""

# Cleanup temp profile (but keep the key info for reference)
echo "🧹 Cleaning up..."
rm -rf "$TEMP_DIR"

echo ""
echo "🎉 Deployment Complete!"
echo "======================"
echo ""
echo "📝 NEW Module Address: $DEPLOY_ADDRESS_FULL"
echo ""
echo "⚠️  IMPORTANT: Update these files with the new module address:"
echo ""
echo "   1. trusted-verifier/config/verifier_testnet.toml:"
echo "      intent_module_address = \"$DEPLOY_ADDRESS_FULL\""
echo ""
echo "   2. solver/config/solver_testnet.toml:"
echo "      module_address = \"$DEPLOY_ADDRESS_FULL\""
echo ""
echo "💡 Next steps:"
echo "   1. Update the config files above with the new module address"
echo "   2. Proceed to deploy EVM IntentEscrow to Base Sepolia (if needed)"
echo ""
