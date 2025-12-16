#!/bin/bash

# Balance Check Script for EVM E2E Tests
# Displays and validates final balances for Hub (Chain 1) and Connected EVM (Chain 3)

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root
setup_project_root

# Get test tokens addresses
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1" 2>/dev/null) || true
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true
USDXYZ_ADDRESS="$USDXYZ_EVM_ADDRESS"

if [ -z "$TEST_TOKENS_CHAIN1" ]; then
    echo "⚠️  Warning: test-tokens-chain1 profile not found, skipping USDxyz balances"
    display_balances_hub
else
    display_balances_hub "0x$TEST_TOKENS_CHAIN1"
fi

if [ -z "$USDXYZ_ADDRESS" ]; then
    echo "⚠️  Warning: USDXYZ_EVM_ADDRESS not found, skipping USDxyz balances"
    display_balances_connected_evm
else
    display_balances_connected_evm "$USDXYZ_ADDRESS"
fi

# Validate solver received escrow funds
# For inflow: Solver starts with 1 USDxyz, receives 1 from escrow = 2 USDxyz
EXPECTED_SOLVER_USDXYZ="2000000"
SOLVER_EVM_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1)
SOLVER_CHAIN3_USDXYZ=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDXYZ_ADDRESS' ACCOUNT='$SOLVER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1 | grep -E '^[0-9]+$' | tail -1)

if [ "$SOLVER_CHAIN3_USDXYZ" != "$EXPECTED_SOLVER_USDXYZ" ]; then
    echo "❌ ERROR: Solver balance mismatch!"
    echo "   Actual:   $SOLVER_CHAIN3_USDXYZ 10e-6.USDxyz"
    echo "   Expected: $EXPECTED_SOLVER_USDXYZ 10e-6.USDxyz"
    exit 1
fi
echo "✅ Solver balance validated: $SOLVER_CHAIN3_USDXYZ 10e-6.USDxyz"
