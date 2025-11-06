#!/bin/bash

# Configure Verifier
# 
# This script extracts deployed contract addresses and updates verifier_testing.toml
# with the current deployment addresses and test account addresses.

set -e

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
cd "$PROJECT_ROOT"

echo "✅ Setup complete! Extracting module addresses..."

# Extract deployed addresses from aptos profiles and update verifier.toml
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

if [ -z "$CHAIN1_ADDRESS" ] || [ -z "$CHAIN2_ADDRESS" ]; then
    echo "❌ ERROR: Could not extract deployed module addresses"
    exit 1
fi

echo "   Chain 1 deployer: $CHAIN1_ADDRESS"
echo "   Chain 2 deployer: $CHAIN2_ADDRESS"

# Use verifier_testing.toml for tests - required, panic if not found
VERIFIER_TESTING_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

# Export config path for Rust code to use (absolute path so tests can find it)
export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

# Update module addresses in verifier_testing.toml
sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN1_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
sed -i "/\[connected_chain\]/,/\[verifier\]/ s|intent_module_address = .*|intent_module_address = \"0x$CHAIN2_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"
sed -i "/\[connected_chain\]/,/\[verifier\]/ s|escrow_module_address = .*|escrow_module_address = \"0x$CHAIN2_ADDRESS\"|" "$VERIFIER_TESTING_CONFIG"

# Get Alice and Bob addresses and update known_accounts
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
ALICE_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')

if [ -n "$ALICE_CHAIN1_ADDRESS" ] && [ -n "$BOB_CHAIN1_ADDRESS" ]; then
    sed -i "/\[hub_chain\]/,/\[connected_chain\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN1_ADDRESS\", \"$BOB_CHAIN1_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

if [ -n "$ALICE_CHAIN2_ADDRESS" ]; then
    sed -i "/\[connected_chain\]/,/\[verifier\]/ s|known_accounts = .*|known_accounts = [\"$ALICE_CHAIN2_ADDRESS\"]|" "$VERIFIER_TESTING_CONFIG"
fi

echo "✅ Updated verifier_testing.toml with deployed addresses"
echo ""

